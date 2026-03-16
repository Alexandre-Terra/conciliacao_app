namespace :tmp do
  desc "Remove temporary conciliation directories older than TMP_CLEANUP_TTL_HOURS (default: 2h). LGPD compliance."
  task cleanup: :environment do
    ttl_hours = ENV.fetch("TMP_CLEANUP_TTL_HOURS", "2").to_i
    cutoff    = ttl_hours.hours.ago
    base      = Rails.root.join("tmp", "conciliacao")

    unless base.exist?
      Rails.logger.info("tmp:cleanup skipped — #{base} does not exist")
      next
    end

    removed = 0
    errors  = 0

    base.children.select(&:directory?).each do |dir|
      next unless dir.mtime < cutoff

      begin
        FileUtils.rm_rf(dir)
        Rails.logger.info(
          "tmp:cleanup removed uuid=#{dir.basename} mtime=#{dir.mtime.utc.iso8601} ttl=#{ttl_hours}h"
        )
        removed += 1
      rescue => e
        Rails.logger.error("tmp:cleanup failed to remove #{dir.basename}: #{e.message}")
        errors += 1
      end
    end

    Rails.logger.info("tmp:cleanup done removed=#{removed} errors=#{errors} cutoff=#{cutoff.utc.iso8601}")
  end
end
