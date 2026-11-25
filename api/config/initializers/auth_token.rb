# Refuse to boot with a JWT signing secret short enough to brute-force.
Rails.application.config.after_initialize { AuthToken.validate_secret! }
