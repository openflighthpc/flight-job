require 'flight_job_helper'
require_relative '../../../lib/flight_job/errors'

RSpec.describe "Invalid scripts" do
  let(:config) { FlightJob.config }
  let(:script_dir) { File.join(config.scripts_dir, script_id) }
  let(:script_id) { "invalid-script" }

  context "invalid script is loaded" do
    it "raises error when loading a single script" do
      # this means that an error would appear if attempting to display
      # information about an invalid script with info-script
      c = FlightJob::Command.new(nil,nil)
      expect { c.load_script(script_id) }.to raise_error(FlightJob::InternalError,
                                                         "Failed to load invalid script: #{script_id}")
    end

    it "loads when loading all scripts" do
      # this means that the invalid script would appear when running list-scripts
      FakeFS.with_fresh do
        FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
        FakeFS::FileSystem.clone(script_dir)

        expect(FlightJob::Script.load_all.length).to eq(1)
      end
    end
  end

  context "invalid script with empty metadata" do
    subject(:script) { FlightJob::Script.new(id: script_id) }

    it "displays script ID" do
      expect(script.id).to eq(script_id)
    end

    %w(template_id script_name created_at).each do |attr|
      it "displays (none) for #{attr}" do
        expect{ script.send(attr) }.not_to raise_error
        expect( script.send(attr) ).to eq(nil)
      end
    end
  end
end
