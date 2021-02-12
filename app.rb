require 'nypl_ruby_util'
require 'aws-sdk-s3'
require 'json'

require_relative 'lib/nypl_core'

def init
  return if $initialized

  $logger = NYPLRubyUtil::NyplLogFormatter.new($stdout, level: ENV['LOG_LEVEL'])
  s3_config = { region: ENV['S3_AWS_REGION'] }
  s3_config[:profile] = ENV['PROFILE'] if ENV['PROFILE']
  $s3_client = Aws::S3::Client.new(s3_config)
  $nypl_core = NyplCore.new

  begin
      raise StandardError.new("missing bucket or locations file") unless ENV['BUCKET'] && ENV['LOCATIONS_FILE']
      locations_response = $s3_client.get_object(bucket: ENV['BUCKET'], key: ENV['LOCATIONS_FILE'])
      $locations = JSON.parse(
        locations_response.body.string
      )
        .map {|k, v| [ Regexp.new(k.gsub('*', '.*')), { code: k, url: v } ]}
        .to_h

  rescue StandardError => e
      $logger.info 'Received s3 error, unable to load locations file from s3', { message: e.message }
      return create_response(500, 'unable to load necessary data from AWS S3')
  end

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
  req_codes = params['location_codes'].split(",")
  records = req_codes.map do |req_code|
    [
      req_code,
      $locations.find {|k,v| k.match? req_code}.map {|k,v| v}
    ]
  end.to_h
rescue StandardError
    $logger.info 'Received error in fetch_locations_and_respond'
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
