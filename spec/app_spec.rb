require 'webmock/rspec'

require_relative '../app'
require_relative './spec_helper'

ENV['BUCKET'] = 'bucket'
ENV['LOCATIONS_FILE'] = 'locations_file'
ENV['LOG_LEVEL'] = 'info'
ENV['NYPL_CORE_S3_BASE_URL'] = 'https://example.com/'

describe :init do
  before(:each) do
    stub_request(:get, ENV['NYPL_CORE_S3_BASE_URL'] + 'by_sierra_location.json')
      .to_return(status: 200, body: File.read('spec/fixtures/by_sierra_location.json'))
  end

  it 'should initialize global variables' do
    mock_s3 = double(Aws::S3::Client)
    mock_response = OpenStruct.new
    mock_response.body = OpenStruct.new
    mock_response.body.string = '{"ag*":"http://fake.com","al*":"http://fakefake.com","ct*":"http://fakewithcoredata.com"}'
    allow(Aws::S3::Client).to receive(:new).and_return(mock_s3)
    allow(mock_s3).to receive(:get_object).and_return(mock_response)
    init
    expect($logger.class).to eq(NYPLRubyUtil::NyplLogFormatter)
    expect($s3_client).to eq(mock_s3)
    expect($locations).to eq(
      {
        'ag*' => 'http://fake.com',
        'al*' => 'http://fakefake.com',
        'ct*' => 'http://fakewithcoredata.com'
      }
    )
    expect($initialized).to eq(true)
  end
end

describe :handle_event do
  before(:each) do
    mock_s3 = double(Aws::S3::Client)
    mock_response = OpenStruct.new
    mock_response.body = OpenStruct.new
    mock_response.body.string = '{"ag*":"http://fake.com","al*":"http://fakefake.com","ct*":"http://fakewithcoredata.com"}'
    allow(Aws::S3::Client).to receive(:new).and_return(mock_s3)
    allow(mock_s3).to receive(:get_object).and_return(mock_response)
    stub_request(:get, ENV['NYPL_CORE_S3_BASE_URL'] + 'by_sierra_location.json')
      .to_return(status: 200, body: File.read('spec/fixtures/by_sierra_location.json'))
  end

  it 'should call init' do
    expect(self).to receive(:init)
    handle_event(event: {}, context: {})
  end

  it 'should respond 501 unless it receives a GET request' do
    expect(
      handle_event(event: { 'httpMethod' => 'PUT' }, context: {})
    ).to eq(create_response(501, 'LocationsService only implements GET endpoints'))
  end

  it 'should load_swagger_docs for swagger path' do
    expect(
      handle_event(
        event: {
          'path' => '/docs/locations',
          'httpMethod' => 'GET'
        },
        context: {}
      )
    ).to eq(load_swagger_docs)
  end

  it 'should invoke fetch_locations_and_respond for locations path' do
    expect(self).to receive(:fetch_locations_and_respond)
    handle_event(
      event: {
        'path' => 'base/locations',
        'httpMethod' => 'GET'
      },
      context: {}
    )
  end

  it 'should respond 404 otherwise' do
    expect(
      handle_event(
        event: {
          'httpMethod' => 'GET',
          'path' => 'fake'
        },
        context: {}
      )
    ).to eq(create_response(404, 'fake not found'))
  end
end

describe 'fetch_locations_and_respond' do
  before(:each) do
    stub_request(:get, 'https://drupal.nypl.org/jsonapi/node/library?filter%5Bfield_ts_library_type%5D=research&jsonapi_include=1&page%5Blimit%5D=125&page%5Boffset%5D=0&sort=title')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Host' => 'drupal.nypl.org',
          'User-Agent' => 'Ruby'
        }
      )
      .to_return(status: 200, body: File.read('spec/fixtures/location_api.json'), headers: {})
  end
  it 'should return the correctly mapped locations with label set to `nil`, if label not available' do
    response = fetch_locations_and_respond({ 'location_codes' => 'ag,al' })
    expect(
      JSON.parse(response[:body], { symbolize_names: true })
    ).to match({
                 ag: [
                   {
                     code: 'ag*',
                     url: 'http://fake.com',
                     label: nil
                   }
                 ],
                 al: [
                   {
                     code: 'al*',
                     url: 'http://fakefake.com',
                     label: nil
                   }
                 ]
               })
  end

  it 'should return the correctly mapped locations with label from NYPL core, if available' do
    response = fetch_locations_and_respond({ 'location_codes' => 'ct,al' })
    expect(
      JSON.parse(response[:body], { symbolize_names: true })
    ).to eq({
              ct: [
                { code: 'ct*', label: 'Fake Park', url: 'http://fakewithcoredata.com' }
              ],
              al: [
                {
                  code: 'al*',
                  label: nil,
                  url: 'http://fakefake.com'
                }
              ]
            })
  end

  it 'if not in locations S3, should still return label from NYPL core, if available' do
    response = fetch_locations_and_respond({ 'location_codes' => 'sa' })
    expect(
      JSON.parse(response[:body], { symbolize_names: true })
    ).to eq({ sa: [{ code: 'sa', label: 'St. A', url: nil }] })
  end
  it 'should return hours when hours is provided as param' do
    expect_any_instance_of(LocationsApi)
      .to receive(:get_location_data)
      .and_return({ hours: 'hours obj', location: 'address obj' })
    data = JSON.parse(fetch_locations_and_respond({ 'location_codes' => 'sc', 'fields' => 'hours' })[:body])
    expect(data['sc'][0]['hours']).to eq 'hours obj'
    expect(data['sc'][0]['location'].nil?).to eq true
  end
  it 'should return hours and location when provided as params' do
    expect_any_instance_of(LocationsApi)
      .to receive(:get_location_data)
      .and_return({ hours: 'hours obj', location: 'address obj' })
    data = JSON.parse(fetch_locations_and_respond({ 'location_codes' => 'sc', 'fields' => 'hours,location' })[:body])
    expect(data['sc'][0]['hours']).to eq 'hours obj'
    expect(data['sc'][0]['location']).to eq 'address obj'
  end
end

# build_location_info_objects
describe 'build_location_info_objects' do
  it 'should not include url if url_query is false' do
    data = build_location_info_objects(false, 'ag')
    expect(data).to eq([{ code: 'ag*', label: nil }])
  end
  it 'if not in locations S3, should still return label from NYPL core, if available' do
    data = build_location_info_objects(true, 'sa')
    expect(data).to eq([{ code: 'sa', label: 'St. A', url: nil }])
  end
  it 'should return the correctly mapped locations with label set to `nil`, if label not available' do
    data = build_location_info_objects(true, 'ag')
    expect(data).to match([{ code: 'ag*', url: 'http://fake.com', label: nil }])
  end
  it 'should not match on location codes that do not start with the location_code_key' do
    data = build_location_info_objects(true, 'mag')
    expect(data[0].keys).not_to include('ag*')
  end
end

describe 'parse_params' do
  it 'returns an array of trues and an array' do
    expect(parse_params({ 'fields' => 'location,hours,url',
                          'location_codes' => 'ma,sc,my' })).to eq([true, true, true, %w[ma sc my]])
  end
  it 'returns an array of mixed values and an array' do
    expect(parse_params({ 'fields' => 'location,url',
                          'location_codes' => 'ma,sc,my' })).to eq([false, true, true, %w[ma sc my]])
  end
  it 'raises an error if no location_codes param' do
    expect { parse_params({ 'fields' => 'location,hours,url' }) }.to raise_error(StandardError)
  end
end

describe 'add_hours_and_location' do
  hours = true
  location = true
  before do
    expect_any_instance_of(LocationsApi)
      .to receive(:get_location_data)
      .and_return({ hours: 'hours', location: 'address' })
  end
  it 'attaches hours and location to array elements' do
    expect(add_hours_and_location('xx', [{}, {}], hours, location)).to eq(
      [
        { hours: 'hours', location: 'address' },
        { hours: 'hours', location: 'address' }
      ]
    )
  end
  it 'can handle an empty array' do
    expect(add_hours_and_location('xx', [], hours, location))
      .to eq([])
  end
  it 'does not change array if hours and location queries are false' do
    expect(add_hours_and_location('xx', [{},{}], false, false))
      .to eq([{}, {}])
  end
end
