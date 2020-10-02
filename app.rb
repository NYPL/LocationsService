require 'nypl_ruby_util'

require_relative 'lib/s3_manager'
require_relative 'lib/locations_manager'

def init
  return if $initialized

  $logger = NYPLRubyUtil::NyplLogFormatter.new($stdout, level: ENV['LOG_LEVEL'])
  $kms_client = NYPLRubyUtil::KmsClient.new
  $s3_client = S3Client.new

  begin
      $s3_client.retrieve_data ENV['LOCATIONS_FILE']
  rescue S3Error => e
      $logger.info 'Received s3 error, unable to load locations file from s3', { message: e.message }
      return create_response(500, 'unable to load necessary data from AWS S3')
  end

  $locations_manager = LocationsManager.new

  $logger.debug 'Initialized function'
  $initialized = true
end

# rubocop:disable Lint/UnusedMethodArgument
def handle_event(event:, context:)
    init

    path = event['path']
    method = event['httpMethod']
    params = event['queryStringParameters']

    $logger.info('handling event', event)

    return create_response(501, 'LocationsService only implements GET endpoints') unless method == 'GET'

    if path == '/docs/locations'
        load_swagger_docs
    elsif /\S+\/locations/.match? path
        fetch_locations_and_respond params
    else
        create_response(404, "#{path} not found")
    end
end

def fetch_locations_and_respond(params)
    records = $locations_manager.fetch_locations params['location_codes']
rescue LocationsManagerError
    $logger.info 'Received LocationsManager error'
    create_response(500, 'Failed to fetch locations by code')
else
    create_response(200, records)
end

def create_response(status_code = 200, body = nil)
    $logger.info "Responding with #{status_code}"

    {
        statusCode: status_code,
        body: JSON.dump(body),
        isBase64Encoded: false,
        headers: { 'Content-type': 'application/json' }
    }
end

def load_swagger_docs
    swagger_docs = JSON.parse(File.read('./swagger.json'))
    create_response(200, swagger_docs)
rescue JSON::JSONError => e
    $logger.error 'Failed to parse Swagger documentation'
    $logger.debug e.message
    create_response(500, 'Unable to load Swagger docs from JSON')
rescue IOError => e
    $logger.error 'Unable to load swagger documentation from file'
    $logger.debug e.message
    create_response(500, 'Unable to load Swagger docs from JSON')
end
