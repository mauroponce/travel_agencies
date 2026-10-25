require "uri"

module Turistack
  class RuntimeConfiguration
    class Invalid < StandardError; end

    PROTECTED_ENVIRONMENTS = %w[staging production].freeze
    DATABASE_VARIABLES = %w[DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME].freeze
    REQUIRED_DATABASE_VARIABLES = %w[DB_HOST DB_USER DB_PASSWORD DB_NAME].freeze
    REQUIRED_RUNTIME_VARIABLES = %w[
      REDIS_URL PLATFORM_BASE_DOMAIN PLATFORM_HOST AUTH_HOST CUSTOM_DOMAIN_CNAME_TARGET
      CADDY_SITE_ADDRESSES GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET ACTIVE_RECORD_ENCRYPTION_KEY
      SECRET_KEY_BASE SMTP_HOST
    ].freeze
    LOCAL_DATABASE_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    PROTECTED_CREDENTIAL_VARIABLES = %w[
      DB_PASSWORD POSTGRES_PASSWORD GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET ACTIVE_RECORD_ENCRYPTION_KEY SECRET_KEY_BASE
    ].freeze
    EXAMPLE_VALUE_PATTERN = /\A(?:change|example|generate|replace|reemplazar|cambiar|generar)(?:\b|_)/i
    HOSTNAME_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

    def self.validate!(environment: Rails.env.to_s, variables: ENV)
      new(environment:, variables:).validate!
    end

    def initialize(environment:, variables:)
      @environment = environment.to_s
      @variables = variables
      @errors = []
    end

    def validate!
      validate_database
      validate_protected_runtime if protected_environment?
      raise Invalid, "Configuración insegura:\n- #{@errors.join("\n- ")}" if @errors.any?

      true
    end

    private

    attr_reader :environment, :variables, :errors

    def validate_database
      url = value("DATABASE_URL")
      configured_fields = DATABASE_VARIABLES.select { |name| value(name).present? }
      errors << "usá DATABASE_URL o DB_*, nunca ambas estrategias" if url.present? && configured_fields.any?

      if url.present?
        validate_database_url(url)
      else
        validate_database_fields
      end

      errors << "RUN_MIGRATIONS ya no está permitido; ejecutá el servicio migrate una sola vez" if value("RUN_MIGRATIONS") == "true"
    end

    def validate_database_url(url)
      uri = URI.parse(url)
      errors << "DATABASE_URL debe usar postgresql:// o postgres://" unless %w[postgres postgresql].include?(uri.scheme)
      validate_database_identity(uri.path.to_s.delete_prefix("/"))
      validate_container_database_host(uri.host)
    rescue URI::InvalidURIError
      errors << "DATABASE_URL no es una URL PostgreSQL válida"
    end

    def validate_database_fields
      if protected_environment?
        missing = REQUIRED_DATABASE_VARIABLES.reject { |name| value(name).present? }
        errors << "faltan variables de PostgreSQL: #{missing.join(', ')}" if missing.any?
      end

      port = value("DB_PORT")
      if port.present? && (!port.match?(/\A\d+\z/) || !(1..65_535).cover?(port.to_i))
        errors << "DB_PORT debe ser un entero entre 1 y 65535"
      end
      validate_database_identity(value("DB_NAME").presence || default_database_name)
      validate_container_database_host(value("DB_HOST"))
      validate_postgres_bootstrap_coherence
    end

    def validate_database_identity(database_name)
      return if database_name.blank? && !protected_environment?

      normalized = database_name.to_s.downcase
      if environment == "test" && value("DB_NAME").present? && !normalized.end_with?("_test")
        errors << "test requiere un DB_NAME terminado en _test"
      elsif environment == "development" && value("DB_NAME").present? && normalized.end_with?("_test", "_production", "_staging")
        errors << "development no puede usar una base de test, staging o producción"
      elsif environment == "staging" && !normalized.include?("staging")
        errors << "staging requiere una base identificable como staging"
      elsif environment == "production" && normalized.match?(/(?:development|_test|staging)/)
        errors << "production no puede usar una base de development, test o staging"
      end
    end

    def validate_container_database_host(host)
      return unless value("CONTAINERIZED") == "true" && LOCAL_DATABASE_HOSTS.include?(host.to_s.downcase)

      errors << "un contenedor no puede usar #{host} como host PostgreSQL; usá el nombre del servicio Docker"
    end

    def validate_postgres_bootstrap_coherence
      return unless value("DB_HOST") == "db"

      { "DB_USER" => "POSTGRES_USER", "DB_PASSWORD" => "POSTGRES_PASSWORD", "DB_NAME" => "POSTGRES_DB" }.each do |app_name, postgres_name|
        next if value(postgres_name).blank? || value(app_name) == value(postgres_name)

        errors << "#{app_name} debe coincidir con #{postgres_name} cuando Rails usa el servicio db"
      end
    end

    def validate_protected_runtime
      missing = REQUIRED_RUNTIME_VARIABLES.reject { |name| value(name).present? }
      errors << "faltan variables obligatorias: #{missing.join(', ')}" if missing.any?
      PROTECTED_CREDENTIAL_VARIABLES.each do |name|
        errors << "#{name} conserva un valor de ejemplo" if value(name).match?(EXAMPLE_VALUE_PATTERN)
      end
      %w[SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_KEY].each do |name|
        errors << "#{name} debe tener al menos 32 caracteres" if value(name).present? && value(name).length < 32
      end
      if value("SECRET_KEY_BASE").present? && value("SECRET_KEY_BASE") == value("ACTIVE_RECORD_ENCRYPTION_KEY")
        errors << "ACTIVE_RECORD_ENCRYPTION_KEY debe ser diferente de SECRET_KEY_BASE"
      end
      errors << "APP_PROTOCOL debe ser https en #{environment}" unless value("APP_PROTOCOL") == "https"
      errors << "FORCE_SSL=false es incompatible con #{environment}" if value("FORCE_SSL") == "false"

      base_domain = normalize_host(value("PLATFORM_BASE_DOMAIN"))
      platform_host = normalize_host(value("PLATFORM_HOST"))
      auth_host = normalize_host(value("AUTH_HOST"))
      cname_target = normalize_host(value("CUSTOM_DOMAIN_CNAME_TARGET"))
      { "PLATFORM_BASE_DOMAIN" => base_domain, "PLATFORM_HOST" => platform_host,
        "AUTH_HOST" => auth_host, "CUSTOM_DOMAIN_CNAME_TARGET" => cname_target }.each do |name, host|
        errors << "#{name} no es un hostname válido" unless host.match?(HOSTNAME_PATTERN)
      end
      errors << "AUTH_HOST debe pertenecer a PLATFORM_BASE_DOMAIN" unless auth_host.end_with?(".#{base_domain}")
      errors << "CUSTOM_DOMAIN_CNAME_TARGET debe pertenecer a PLATFORM_BASE_DOMAIN" unless cname_target.end_with?(".#{base_domain}")
      unless platform_host == base_domain || platform_host.end_with?(".#{base_domain}")
        errors << "PLATFORM_HOST debe ser PLATFORM_BASE_DOMAIN o pertenecer a él"
      end
      errors << "PLATFORM_HOST y AUTH_HOST deben ser diferentes" if platform_host == auth_host

      caddy_hosts = value("CADDY_SITE_ADDRESSES").to_s.split(",").map { |host| normalize_host(host) }
      [ platform_host, auth_host ].each do |host|
        errors << "CADDY_SITE_ADDRESSES debe incluir #{host}" unless caddy_hosts.include?(host)
      end
    end

    def protected_environment? = PROTECTED_ENVIRONMENTS.include?(environment)

    def default_database_name
      "turistack_#{environment}"
    end

    def value(name)
      variables[name].to_s.strip
    end

    def normalize_host(host)
      host.to_s.strip.downcase.delete_suffix(".")
    end
  end
end
