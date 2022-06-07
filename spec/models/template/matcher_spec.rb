require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:config) { FlightJob.config }
  let(:template_id_1) { "template-1" }
  let(:template_id_2) { "template-2" }
  let(:template_name_1) { "Template name 1" }
  let(:template_name_2) { "Template name 2" }

  before(:all) do
    Flight.config.templates_dir = File.join(Flight.root, 'spec/fixtures/templates')
  end

  context "templates are loaded and filtered" do
    it "by only template ID" do
      opts = OpenStruct.new(id: "*-1")
      expect(FlightJob::Template.new(id: template_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Template.new(id: template_id_2).pass_filter?(opts)).to be false
    end
    it "by only template name" do
      opts = OpenStruct.new(name: "* name 2")
      puts config.templates_dir
      expect(FlightJob::Template.new(id: template_id_1).pass_filter?(opts)).to be false
      expect(FlightJob::Template.new(id: template_id_2).pass_filter?(opts)).to be true
    end
  end

  context "templates are loaded with no filter" do
    it "all templates are loaded" do
      opts = OpenStruct.new
      expect(FlightJob::Template.new(id: template_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Template.new(id: template_id_2).pass_filter?(opts)).to be true
    end
  end
end