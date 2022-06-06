require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:template_id_1) { "template-1" }
  let(:template_id_2) { "template-2" }

  context "templates are loaded and filtered" do
    it "by only template ID" do
      opts = OpenStruct.new(id: "*log*")
      expect(FlightJob::Template.new(id: template_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Template.new(id: template_id_2).pass_filter?(opts)).to be false
    end
    it "by only template name" do
      opts = OpenStruct.new(template: "*com*")
      expect(FlightJob::Template.new(id: template_id_1).pass_filter?(opts)).to be false
      expect(FlightJob::Template.new(id: template_id_2).pass_filter?(opts)).to be true
    end
  end
end