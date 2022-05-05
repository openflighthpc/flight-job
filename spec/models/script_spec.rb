require 'flight_job_helper'

RSpec.describe "FlightJob::Script", type: :model do
  let(:config) { FlightJob.config }
  let(:metadata_path) { File.join(script_dir,"metadata.yaml") }
  let(:script_dir) { File.join(config.scripts_dir, script_id) }

  describe "script creation" do
    let(:script_id) { "new-script" }
    let(:template_id) { "desktop-on-login-node" }
    let(:script_name) { "interactive-desktop.sh" }
    let(:notes_path) { File.join(script_dir,"notes.md") }
    let(:job_script_path) { File.join(script_dir,"script.sh") }

    it "writes the notes"

    it "writes the job script file"

    it "writes the metadata" do
      FakeFS do
        check_for_file_creation(metadata_path)
      end
    end

    def check_for_file_creation(file_path)
      #FakeFS::FileSystem.clone(File.join(__FILE__, "../../../config"))
      FakeFS::FileSystem.clone(config.templates_dir)
      FakeFS::FileSystem.clone(config.adapter_script_path)

      expect(File).not_to exist(file_path)
      script = FlightJob::Script.new(
        id: script_id,
        template_id: template_id,
        script_name: script_name,
        )
      script.render_and_save
      expect(File).to exist(file_path)
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
