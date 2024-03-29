# Deprecated
The `locations` endpoint is served by a [python app](https://github.com/NYPL/locations-service/) as of 10/10/2023.

# LocationsService

Function that returns data for locations by code. Currently only urls are implemented. This retrieves the data set by the LocationsPoller


## Request/Response Structure

Serves `/locations?location_codes=code1,code2...`

Will respond with JSON as below:

```
{
  code1: {
    code: [matching code 1],
    url: [url]
  },
  code2: {
    code: [matching code 2],
    url: [url]
  }
}
```

## Requirements

- ruby 2.7

## Environment variables

- LOG_LEVEL: e.g. 'info' or 'debug', sets the verbosity of the logs

- S3_AWS_REGION: usually 'us-east-1', the region in which to find the locations s3

- BUCKET: the name of the locations s3

- LOCATIONS_FILE: the name of the file in the s3 bucket that contains the locations

- NYPL_CORE_S3_BASE_URL: base url for the S3 file containing `nypl-core` data

- PROFILE: optional, useful for local testing.

## Installation

This function is developed using the AWS SAM framework, [which has installation instructions here](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

To install the dependencies for this function, they must be bundled for this framework and should be done with `rake run_bundler`

## Usage

To run the function locally it may be invoked with rake, where FUNCTION is the name of the function you'd like to invoke from the `sam.local.yml` file:

`rake run_local`

## Testing

Testing is provided via `rspec`. The test suite can be invoked with `rake test`

## Running Server Locally
To run the server locally:
- First, run `bundle install --deployment` with matching Ruby version (2.7) running
- Then, run `sam local start-api --template sam.local.yml`
- Visit this url replacing `[location_codes]` with the list of locations code being checked `http://127.0.0.1:3000/api/v0.1/locations?location_codes=[location_codes]`
