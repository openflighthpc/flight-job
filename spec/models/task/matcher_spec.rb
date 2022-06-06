require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:task_id_1) { "task-1" }
  let(:task_id_2) { "task-2" }

  context "tasks are loaded and filtered" do
    it "by task state" do
      opts = OpenStruct.new(id: "*log*")
      expect(FlightJob::Task.new(id: task_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Task.new(id: task_id_2).pass_filter?(opts)).to be false
    end
  end
end