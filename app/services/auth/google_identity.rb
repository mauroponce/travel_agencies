module Auth
  class GoogleIdentity
    class InvalidIdentity < StandardError; end

    def self.call(auth) = new(auth).call

    def initialize(auth)
      @auth = auth
    end

    def call
      uid = @auth["uid"].to_s
      info = @auth["info"] || {}
      claims = @auth.dig("extra", "id_info") || {}
      email = info["email"].to_s.downcase
      verified = [ true, "true" ].include?(claims["email_verified"])
      raise InvalidIdentity, "Google no confirmó el correo de esta cuenta." unless uid.present? && email.present? && verified

      user = User.find_or_initialize_by(google_sub: uid)
      conflict = User.where.not(id: user.id).find_by("lower(email) = ?", email)
      raise InvalidIdentity, "Ese correo ya está vinculado a otra identidad de Google." if conflict

      user.update!(email:, name: info["name"].presence || email.split("@").first, avatar_url: info["image"])
      provision_operator(user)
      user
    end

    private

    def provision_operator(user)
      PlatformOperatorAccess.synchronize!(user)
    end
  end
end
