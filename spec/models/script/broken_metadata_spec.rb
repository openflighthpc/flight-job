require 'flight_job_helper'

RSpec.describe "Invalid scripts" do
  let(:config) { FlightJob.config }
  let(:script_dir) { File.join(config.scripts_dir, script_id) }
  let(:metadata_path) { File.join(config.script_dir, "metadata.yaml") }
  let(:script_id) { "invalid-script" }

  # context "invalid script is loaded" do
  #   it "loads when loading a single script" do
  #     # this means that the invalid script would appear when running info-script
  #     FakeFS.with_fresh do
  #       FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
  #       FakeFS::FileSystem.clone(script_dir)
  #
  #       x = FlightJob::Command.new(nil,nil)
  #       expect(x.load_script(script_id)).to be_truthy
  #     end
  #   end
  #
  #   it "loads when loading all scripts" do
  #     # this means that the invalid script would appear when running list-scripts
  #     FakeFS.with_fresh do
  #       FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
  #       FakeFS::FileSystem.clone(script_dir)
  #
  #       expect(FlightJob::Script.load_all.length).to eq(1)
  #     end
  #   end
  # end
end