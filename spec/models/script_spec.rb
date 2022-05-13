require 'flight_job_helper'

RSpec.describe "FlightJob::Script", type: :model do
  let(:config) { FlightJob.config }
  let(:metadata_path) { File.join(script_dir,"metadata.yaml") }
  let(:script_dir) { File.join(config.scripts_dir, script_id) }
  let(:template_id) { "desktop-on-login-node" }
  let(:template) { FlightJob::Template.new(id: template_id) }

  describe "script creation" do
    let(:script_id) { "new-script" }
    let(:script_name) { "interactive-desktop.sh" }
    let(:notes_path) { File.join(script_dir,"notes.md") }
    let(:job_script_path) { File.join(script_dir,"script.sh") }

    it "writes the notes" do
      check_for_file_creation(notes_path)
    end

    it "writes the job script file" do
      check_for_file_creation(job_script_path)
    end

    it "writes the metadata" do
      check_for_file_creation(metadata_path)
    end
  end

  def check_for_file_creation(file_path)
    FakeFS.with_fresh do
      FakeFS::FileSystem.clone(config.templates_dir)
      FakeFS::FileSystem.clone(config.adapter_script_path)
      FakeFS::FileSystem.clone("/tmp/bundle/ruby/2.7.0/gems/activesupport-6.1.3")
      FakeFS::FileSystem.clone("/tmp/bundle/ruby/2.7.0/gems/activemodel-6.1.3")

      expect(File).not_to exist(file_path)
      FlightJob::Script.new( id: script_id ).tap do |s|
        s.initialize_metadata(template, {})
        s.render_and_save
      end
      expect(File).to exist(file_path)
    end
  end


  describe "metadata" do
    let(:script_id) { "valid-script" }
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

    it "reads generation_answers from the metadata defaulting to {}" do
      expect(script.answers).to eq(metadata["answers"] || {})
    end

    {
      template_id: 'foo',
      script_name: 'bar',
      tags: %w[a b c],
    }.each do |attr, value|
      it "writes #{attr} to the metadata" do
        expect(script.send(attr)).not_to eq(value)
        script.metadata.send("#{attr}=", value)
        expect(script.send(attr)).to eq(value)
      end
    end

    it "writes the file contents correctly" do
      FakeFS.with_fresh do
        FakeFS::FileSystem.clone(config.templates_dir)
        FakeFS::FileSystem.clone(config.adapter_script_path)

        FlightJob::Script.new(id: script_id).tap do |s|
          s.initialize_metadata(template, {})
          s.render_and_save
        end
        new_script = FlightJob::Script.new(id: script_id)

        %w(created_at script_name tags template_id).each do |attr|
          expect(new_script.send(attr)).to eq(metadata[attr])
        end
      end
    end
  end
end
