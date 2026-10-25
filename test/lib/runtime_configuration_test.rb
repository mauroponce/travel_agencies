require "test_helper"
require Rails.root.join("lib/turistack/runtime_configuration")

class RuntimeConfigurationTest < ActiveSupport::TestCase
  test "rejects mixing DATABASE_URL with DB variables" do
    error = assert_raises(Turistack::RuntimeConfiguration::Invalid) do
      validate("development", "DATABASE_URL" => "postgresql://user:secret@localhost/turistack_development",
        "DB_HOST" => "db")
    end

    assert_includes error.message, "nunca ambas estrategias"
    assert_not_includes error.message, "secret"
  end

  test "rejects unsafe database identities in every environment" do
    assert_invalid("development", { "DB_NAME" => "turistack_production" }, "development no puede")
    assert_invalid("test", { "DB_NAME" => "turistack_development" }, "test requiere")
    assert_invalid("staging", protected_variables.merge("DB_NAME" => "turistack_production"), "identificable como staging")
    assert_invalid("production", protected_variables.merge("DB_NAME" => "turistack_test"), "production no puede")
  end

  test "rejects localhost and incoherent bootstrap credentials inside containers" do
    assert_invalid("production", protected_variables.merge("DB_HOST" => "localhost"), "nombre del servicio Docker")
    assert_invalid("production", protected_variables.merge("POSTGRES_DB" => "otra_base"),
      "DB_NAME debe coincidir con POSTGRES_DB")
  end

  test "rejects a malformed PostgreSQL port" do
    assert_invalid("development", { "DB_PORT" => "5432oops" }, "DB_PORT debe ser un entero")
  end

  test "requires HTTPS and explicit protected environment settings" do
    assert_invalid("production", protected_variables.merge("APP_PROTOCOL" => "http"), "APP_PROTOCOL debe ser https")
    assert_invalid("staging", protected_variables.except("GOOGLE_CLIENT_SECRET"), "GOOGLE_CLIENT_SECRET")
    assert_invalid("production", protected_variables.merge("ACTIVE_RECORD_ENCRYPTION_KEY" => "s" * 64),
      "debe ser diferente de SECRET_KEY_BASE")
  end

  test "rejects example values and short application keys in protected environments" do
    assert_invalid("production", protected_variables.merge("GOOGLE_CLIENT_SECRET" => "reemplazar"),
      "GOOGLE_CLIENT_SECRET conserva un valor de ejemplo")
    assert_invalid("staging", protected_variables.merge("DB_NAME" => "turistack_staging",
      "POSTGRES_DB" => "turistack_staging", "SECRET_KEY_BASE" => "short"),
      "SECRET_KEY_BASE debe tener al menos 32 caracteres")
  end

  test "requires the platform host to belong to the configured base domain" do
    assert_invalid("production", protected_variables.merge("PLATFORM_HOST" => "turistack.example.net",
      "CADDY_SITE_ADDRESSES" => "turistack.example.net, auth.turistack.com"),
      "PLATFORM_HOST debe ser PLATFORM_BASE_DOMAIN o pertenecer a él")
  end

  test "accepts exclusive URL and DB field strategies" do
    assert validate("development", "DATABASE_URL" => "postgresql://user:secret@localhost/turistack_development")
    assert validate("test", {})
    assert validate("production", protected_variables)
    assert validate("staging", protected_variables.merge("DB_NAME" => "turistack_staging", "POSTGRES_DB" => "turistack_staging"))
  end

  test "does not include database passwords in validation messages" do
    variables = protected_variables.merge("DB_PASSWORD" => "top-secret", "POSTGRES_PASSWORD" => "other-secret")
    error = assert_raises(Turistack::RuntimeConfiguration::Invalid) { validate("production", variables) }

    assert_includes error.message, "DB_PASSWORD debe coincidir con POSTGRES_PASSWORD"
    assert_not_includes error.message, "top-secret"
    assert_not_includes error.message, "other-secret"
  end

  private

  def validate(environment, variables)
    Turistack::RuntimeConfiguration.new(environment:, variables: variables.stringify_keys).validate!
  end

  def assert_invalid(environment, variables, message)
    error = assert_raises(Turistack::RuntimeConfiguration::Invalid) { validate(environment, variables) }
    assert_includes error.message, message
  end

  def protected_variables
    {
      "CONTAINERIZED" => "true",
      "DB_HOST" => "db",
      "DB_PORT" => "5432",
      "DB_USER" => "turistack",
      "DB_PASSWORD" => "secret",
      "DB_NAME" => "turistack_production",
      "POSTGRES_USER" => "turistack",
      "POSTGRES_PASSWORD" => "secret",
      "POSTGRES_DB" => "turistack_production",
      "REDIS_URL" => "redis://redis:6379/0",
      "PLATFORM_BASE_DOMAIN" => "turistack.com",
      "PLATFORM_HOST" => "turistack.com",
      "AUTH_HOST" => "auth.turistack.com",
      "CUSTOM_DOMAIN_CNAME_TARGET" => "tenants.turistack.com",
      "CADDY_SITE_ADDRESSES" => "turistack.com, auth.turistack.com",
      "GOOGLE_CLIENT_ID" => "client-id",
      "GOOGLE_CLIENT_SECRET" => "client-secret",
      "SECRET_KEY_BASE" => "s" * 64,
      "ACTIVE_RECORD_ENCRYPTION_KEY" => "e" * 64,
      "SMTP_HOST" => "smtp.example.com",
      "APP_PROTOCOL" => "https"
    }
  end
end
