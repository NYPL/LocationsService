require 'webmock/rspec'

require_relative '../app'
require_relative './spec_helper'

ENV['BUCKET'] = 'bucket'
ENV['LOCATIONS_FILE'] = 'locations_file'
ENV['LOG_LEVEL'] = 'info'
ENV['NYPL_CORE_S3_BASE_URL'] = 'https://example.com/'

describe :init do
  before(:each) do
    stub_request(:get, ENV['NYPL_CORE_S3_BASE_URL'] + "by_sierra_location.json")
    .to_return(status: 200, body: File.read("spec/fixtures/by_sierra_location.json"))
  end

  it 'should initialize global variables' do
      mock_s3 = double(Aws::S3::Client)
      mock_response = OpenStruct.new
      mock_response.body = OpenStruct.new
      mock_response.body.string = "{\"ag*\":\"http://fake.com\",\"al*\":\"http://fakefake.com\",\"ct*\":\"http://fakewithcoredata.com\"}"
      allow(Aws::S3::Client).to receive(:new).and_return(mock_s3)
      allow(mock_s3).to receive(:get_object).and_return(mock_response)
      init
      expect($logger.class).to eq(NYPLRubyUtil::NyplLogFormatter)
      expect($s3_client).to eq(mock_s3)
      expect($locations).to eq(
        {
          /ag.*/=>{:code=>"ag*", :url=>"http://fake.com"},
          /al.*/=>{:code=>"al*", :url=>"http://fakefake.com"},
          /ct.*/=>{:code=>"ct*", :url=>"http://fakewithcoredata.com"}
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
    mock_response.body.string = "{\"ag*\":\"http://fake.com\",\"al*\":\"http://fakefake.com\",\"ct*\":\"http://fakewithcoredata.com\"}"
    allow(Aws::S3::Client).to receive(:new).and_return(mock_s3)
    allow(mock_s3).to receive(:get_object).and_return(mock_response)
    stub_request(:get, ENV['NYPL_CORE_S3_BASE_URL'] + "by_sierra_location.json")
    .to_return(status: 200, body: File.read("spec/fixtures/by_sierra_location.json"))
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
    ).to eq(create_response(404, "fake not found"))
  end
end

describe 'fetch_locations_and_respond' do
  it 'should return the correctly mapped locations with label set to `nil`, if label not available' do
    expect(
      fetch_locations_and_respond({ 'location_codes' => 'ag,al' })
    ).to eq(
      {
        :body => {
          "ag" => [
            {
              :code => "ag*",
              :url => "http://fake.com",
              :label => nil
            }
          ],
          "al" => [
            {
              :code => "al*",
              :url => "http://fakefake.com",
              :label => nil
            }
          ]
        }.to_json,
        :headers => {
          :"Content-type" => "application/json"
        },
        :isBase64Encoded => false,
        :statusCode => 200
      }
    )
  end

  it 'should return the correctly mapped locations with label from NYPL core, if available' do
    expect(
      fetch_locations_and_respond({ 'location_codes' => 'ct,al' })
    ).to eq(
      {
        :body => {
          "ct" => [
            {
              :code => "ct*",
              :url => "http://fakewithcoredata.com",
              :label => "Fake Park"
            }
          ],
          "al" => [
            {
              :code => "al*",
              :url => "http://fakefake.com",
              :label => nil
            }
          ]
        }.to_json,
        :headers => {
          :"Content-type" => "application/json"
        },
        :isBase64Encoded => false,
        :statusCode => 200
      }
    )
  end

  it 'if not in locations S3, should still return label from NYPL core, if available' do
    expect(
      fetch_locations_and_respond({ 'location_codes' => 'sa' })
    ).to eq(
      {
        :body => {
          "sa" => [
            {
              :code => "sa",
              :label => "St. A",
              :url => nil
            }
          ]
        }.to_json,
        :headers => {
          :"Content-type" => "application/json"
        },
        :isBase64Encoded => false,
        :statusCode => 200
      }
    )
  end
end
