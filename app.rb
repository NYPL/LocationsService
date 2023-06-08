require 'nypl_ruby_util'
require 'aws-sdk-s3'
require 'json'

require_relative 'lib/nypl_core'
require_relative 'lib/locations_api'

def init
  return if $initialized

  $logger = NYPLRubyUtil::NyplLogFormatter.new($stdout, level: ENV['LOG_LEVEL'])
  s3_config = { region: ENV['S3_AWS_REGION'] }
  s3_config[:profile] = ENV['PROFILE'] if ENV['PROFILE']
  $s3_client = Aws::S3::Client.new(s3_config)
  $nypl_core = NyplCore.new
  $locations_api = LocationsApi.new

  begin
    raise StandardError, 'missing bucket or locations file' unless ENV['BUCKET'] && ENV['LOCATIONS_FILE']

    locations_response = $s3_client.get_object(bucket: ENV['BUCKET'], key: ENV['LOCATIONS_FILE'])
    $locations = JSON.parse(
      locations_response.body.string
    )
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
  elsif %r{\S+/locations}.match? path
    fetch_locations_and_respond params
  else
    create_response(404, "#{path} not found")
  end
end

def parse_params(params)
  if params['location_codes'].nil?
    raise StandardError.new 'No location codes provided.'
  end
  hours_query = false
  location_query = false
  url_query = false

  if !params['fields'].nil?
    fields = params['fields'].split(',')
    hours_query = fields.include?('hours')
    location_query = fields.include?('location')
    url_query = fields.include?('url')
  else
    url_query = true
  end
  location_codes = params['location_codes'].split(',')
  [hours_query, location_query, url_query, location_codes]
end

def fetch_locations_and_respond(params)
  hours_query, location_query, url_query, location_codes = parse_params params
  records = location_codes.map do |location_code|
    data = build_location_info_objects(url_query, location_code)
    [
      location_code,
      add_hours_and_location(location_code, data, hours_query, location_query)
    ]
  end.to_h
rescue StandardError => e
  $logger.warn "Received error in fetch_locations_and_respond. Message: #{e.message}"
  create_response(500, 'Failed to fetch locations by code')
else
  create_response(200, records)
end

def build_location_info_objects(url_query, location_code)
  # extract the label from $nypl_core
  core_data = $nypl_core.check_sierra_location(location_code) || {}
  label = core_data['label'] || nil
  # We are allowing for the possibility of
  # a location code having two entries in $locations
  # iterate over locations to find any match(es)
  data = $locations.select do |location_code_key, _url|
           Regexp.new('^'+location_code_key.gsub('*', '.*')).match? location_code
         end
                   .map do |location_code_key, url_value|
    location_info = { label: label, code: location_code_key }
    location_info[:url] = url_value if url_query
    location_info
  end
  # if location_code is missing in s3 locations lookup, we still want to
  # include it in response, so create object here:
  data = [{ code: location_code, url: nil, label: label }] if data.length.zero?
  data
end

def add_hours_and_location(location_code, data, hours_query, location_query)
  # fetch hours and location info from drupal locations api
  hours_and_location_data = $locations_api.get_location_data(location_code)
  # the hours and location for two location codes starting with the same letters
  # will be the same, so add the same information to each element
  data.map do |location_info|
    location_info[:hours] = hours_and_location_data[:hours] if hours_query
    location_info[:location] = hours_and_location_data[:location] if location_query
    location_info
  end
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
