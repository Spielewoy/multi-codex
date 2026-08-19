# frozen_string_literal: true

SimpleCov.root Dir.pwd
SimpleCov.coverage_dir ENV.fetch(
  "BASH_COVERAGE_OUTPUT",
  File.join(ENV.fetch("TMPDIR", "/tmp"), "multi-cli-coverage", "bash")
)
SimpleCov.track_files "{multi-cli,lib/*.sh,scripts/*.sh,install/*.sh,release/*.sh}"
SimpleCov.add_filter "/tests/"
