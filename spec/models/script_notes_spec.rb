require 'flight_job_helper'

RSpec.describe "FlightJob::Notes", type: :model do
  let(:config) { FlightJob.config }
  let(:script_id) { "script-id" }
  let(:script_dir) { File.join(config.scripts_dir, script_id) }
  let(:template) { FlightJob::Template.new(id: "desktop-on-login-node") }
  let(:test_notes) { "test notes" }
  let(:notes_path) { File.join(script_dir,"notes.md") }

  context "writes notes for a new script" do
    it "creates the notes file" do
      fresh_fakefs do
        expect(File).not_to exist(notes_path)
        create_and_save_script
        expect(File).to exist(notes_path)
      end
    end

    it "saves the notes correctly" do
      fresh_fakefs do
        create_and_save_script(notes: test_notes)
        new_script = FlightJob::Script.new(id: script_id)
        expect(new_script.notes.read).to eq(test_notes)
      end
    end
  end

  context "edits notes for an existing script" do
    let(:new_notes) { "New test notes" }

    it "new notes are saved correctly" do
      fresh_fakefs do
        create_and_save_script(notes: test_notes).tap do |script|
          script.notes.save(new_notes)
        end
        new_script = FlightJob::Script.new(id: script_id)
        expect(new_script.notes.read).to eq(new_notes)
      end
    end
  end

  def fresh_fakefs
    FakeFS.with_fresh do
      FakeFS::FileSystem.clone(config.templates_dir)
      FakeFS::FileSystem.clone(config.adapter_script_path)
      yield
    end
  end

  def create_and_save_script(id: script_id, notes: "")
    FlightJob::Script.new( id: id ).tap do |s|
      s.initialize_metadata(template, {})
      s.initialize_notes(notes)
      s.render_and_save
    end
  end
end
