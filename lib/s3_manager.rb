require 'aws-sdk-s3'

# Class for managing the state of the poller in S3
class S3Client
    # Create S3 client
    def initialize
        @s3 = Aws::S3::Client.new(region: ENV['AWS_REGION'])
    end

    def store_data(file)
        $logger.info "Storing #{file} in s3 for retrieval by check-in card API"

        # Read file into memory
        sql_data = File.read("/tmp/#{file}")

        # Store file in s3
        begin
            @s3.put_object({
                body: sql_data,
                bucket: ENV['SQLITE_BUCKET'],
                key: file,
            })
        rescue StandardError => e
            $logger.error 'Unable to store sqlite db in s3', { status: e.message }
            raise S3Error, 'Unable to store sqlite db in s3'
        end
    end

    def retrieve_data(file)
        $logger.info "Fetching #{file} from s3 bucket"

        begin
            File.open("/tmp/#{file}", 'wb') do |f|
                @s3.get_object(bucket: ENV['SQLITE_BUCKET'], key: file) do |chunk|
                    f.write(chunk)
                end
            end
        rescue StandardError => e
            $logger.error 'Unable to rertrieve file from s3', { status: e.message }
            raise S3Error, 'Unable to retrieve file from s3'
        end
    end
end

class S3Error < StandardError; end
