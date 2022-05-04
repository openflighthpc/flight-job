require 'flight_job_helper'

RSpec.describe "FlightJob::Script", type: :model do
  let(:config) { FlightJob.config }

  describe "script creation" do
    let(:script_id) { "new-script" }
    let(:template_id) { "desktop-on-login-node" }
    let(:script_name) { "interactive-desktop.sh" }
    let(:script_dir) { File.join(config.scripts_dir, script_id) }
    let(:metadata_path) { File.join(script_dir,"metadata.yaml") }
    let(:answers) { {"working_dir"=>"~", "stdout_file"=>"job-%j.output", "merge_stderr_with_stdout"=>"yes", "notification_wanted"=>"no"} }
    let(:tags) { ["script:type=interactive", "session:type=desktop", "session:order=desktop:alloc"] }

    it "writes the notes"

    it "writes the job script file"

    it "writes the metadata" do
      FakeFS do
        FakeFS::FileSystem.clone(File.join(__FILE__, "../../../config"))
        FakeFS::FileSystem.clone(script_dir)

        expect(File).not_to exist(metadata_path)
        opts = ( script_id ? { id: script_id } : {} )
        script = FlightJob::Script.new(
          id: script_id,
          template_id: template_id,
          script_name: script_name,
          answers: answers,
          notes: "",
          tags: tags,
          **opts
        )
        script.render_and_save
        expect(File).to exist(metadata_path)
      end
    end
  end

  describe "metadata" do
    let(:script_id) { "valid-script" }
    let(:script_dir) { File.join(config.scripts_dir, script_id) }
    let(:metadata_path) { File.join(script_dir,"metadata.yaml") }
    let(:metadata) { YAML.load_file(metadata_path) }

    subject(:script) { FlightJob::Script.new(id: script_id) }

    it "has the expected metadata path" do
      expect(script.metadata_path).to eq(metadata_path)
    end

    %w(created_at script_name tags template_id).each do |attr|
      it "reads #{attr} from the metadata" do
        expect(script.send(attr)).to eq(metadata[attr])
      end
    end

    it "reads submission_answers from the metadata defaulting to {}" do
      expect(script.answers).to eq(metadata["answers"] || {})
    end
  end
end
