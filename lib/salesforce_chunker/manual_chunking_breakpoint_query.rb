require "pry"

module SalesforceChunker
  class ManualChunkingBreakpointQuery < Job

    def initialize(connection:, object:, operation:, query:, **options)
      @batch_size = options[:batch_size] || 1000
      super(connection: connection, object: object, operation: operation, **options)

      @log.info "Creating Breakpoint Query"
      @batch_id = create_batch(query)
      @batches_count = 1
      close
    end

    def get_batch_results(batch_id)
      retrieve_batch_results(batch_id).each do |result_id|
        results = retrieve_results(batch_id, result_id)

        lines = results.each_line
        headers = lines.next
        first_line = lines.next

        loop do
          begin
            (@batch_size-1).times { lines.next }
            yield(lines.next.chomp.gsub("\"", ""))
          rescue StopIteration
            break
          end
        end
      end
    end

    def create_batch(payload)
      @log.info "Creating Id Batch: \"#{payload.gsub(/\n/, " ").strip}\""
      response = @connection.post("job/#{@job_id}/batch", payload.to_s, {"Content-Type": "text/csv"})
      response["batchInfo"]["id"]
    end

    def retrieve_batch_results(batch_id)
      # XML to JSON wrangling
      response = super(batch_id)
      if response["result_list"]["result"].is_a? Array
        response["result_list"]["result"]
      else
        [response["result_list"]["result"]]
      end
    end

    def get_batch_statuses
      # XML to JSON wrangling
      #binding.pry
      #super["batchInfoList"]
      [@connection.get_json("job/#{@job_id}/batch")["batchInfoList"]["batchInfo"]]
    end

    def create_job(object, options)
      body = {
        "operation": @operation,
        "object": object,
        "contentType": "CSV",
      }
      body[:externalIdFieldName] = options[:external_id] if @operation == "upsert"
      @connection.post_json("job", body, options[:headers].to_h)["id"]
    end
  end
end
