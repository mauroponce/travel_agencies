redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
  schedule_file = Rails.root.join("config/sidekiq_schedule.yml")
  Sidekiq::Cron::Job.load_from_hash(YAML.safe_load_file(schedule_file)) if schedule_file.exist?
end

Sidekiq.configure_client { |config| config.redis = { url: redis_url } }
