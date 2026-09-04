# Wraps Typhoeus request in a fiber, resumes the fiber in callbacks.
# Catches exceptions from the on_complete callback and stores them on the downloader
# to prevent them from being swallowed by the event loop.
class RMT::FiberRequest < RMT::HttpRequest
  attr_accessor :base_url, :download_path, :remote_file

  def initialize(base_url, download_path:, request_fiber:, downloader:, **options)
    @base_url = base_url
    @download_path = download_path
    @request_fiber = request_fiber
    @remote_file = base_url.split('?').first
    @downloader = downloader

    super(base_url, options)

    on_headers { |response| @request_fiber.resume(response) }
    on_body do |chunk|
      next :abort if @download_path.closed?
      @download_path.write(chunk)
    end
    on_complete do |response|
      @request_fiber.resume(response)
    rescue StandardError => e
      @downloader.raised_exceptions << e
    end
  end

  def receive_headers
    Fiber.yield(self)
  end

  def receive_body
    response = read_body

    if (response.return_code && response.return_code != :ok)
      raise 'Error while processing the response.'
    end

    @download_path.close
    response
  rescue StandardError
    @download_path.unlink
    response
  end

  protected

  # helper method for specs
  def read_body
    Fiber.yield
  end

end
