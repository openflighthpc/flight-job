module FlightJob
  module Matchers
    module Model
      extend RSpec::Matchers::DSL
      
      matcher :have_error do |*expected|
        match do |record|
          record.errors.of_kind?(*expected)
        end

        failure_message do |record|
          "expected record to have error #{expected} has errors #{record.errors.details}" 
        end
      end
    end
  end
end
