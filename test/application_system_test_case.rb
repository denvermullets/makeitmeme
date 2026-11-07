# Cable's test adapter only records broadcasts. System tests need real delivery to the browser, so ask
# config/cable.yml for the async adapter (the server runs in-process). Must be set before the environment loads.
ENV['SYSTEM_TESTS'] = '1'

require 'test_helper'

# Browser tests. Run on their own with `bin/rails test:system`: `bin/rails test` and CI skip them, and they need a
# local Chrome. A phone-sized window, since the game is played on phones.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [390, 844]

  setup do
    # Deadline jobs (PhaseDeadlineJob) run in-process and on time; the recurring sweep is not needed.
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :async
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end
end
