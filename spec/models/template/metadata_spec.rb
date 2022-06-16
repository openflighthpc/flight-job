require 'flight_job_helper'

RSpec.describe "Template::Metadata", type: :model do
  let(:config) { FlightJob.config }
  let(:template_id) { "valid-template" }
  let(:template) { FlightJob::Template.new(id: template_id) }
  let(:template_dir) { File.join(config.templates_dir, template_id) }
  let(:metadata) { YAML.load_file(metadata_path) }
  let(:metadata_path) { File.join(template_dir,"metadata.yaml") }

  before(:all) do
    @templates_dir = Flight.config.templates_dir
    Flight.config.templates_dir = File.join(Flight.root, 'spec/fixtures/templates')
  end
  after(:all) do
    Flight.config.templates_dir = @templates_dir
  end

  context "metadata attributes" do
    it "has the expected path" do
      expect(template.metadata.path).to eq(metadata_path)
    end

    %w(
      synopsis
      version
      name
      copyright
      license
      description
      script_template
      priority
      __meta__
    ).each do |attr|
      it "reads #{attr} correctly" do
        expect(template.send(attr)).to eq(metadata[attr])
      end
    end

    %w(generation_questions submission_questions).each do |questions|
      it "reads #{questions} correctly" do
        _questions = metadata[questions].map do |datum|
          FlightJob::Question.new(**datum.symbolize_keys)
        end
        _questions.each_with_index do |q, index|
          %w(id text description).each do |attr|
            expect(template.send(questions)[index].send(attr)).to eq(q.send(attr))
          end
        end
      end
    end

  end

  context "valid metadata" do
    let(:template_id) { "valid-template" }

    it "raises no errors" do
      template.valid?
      expect(template.errors).to be_empty
    end
  end

  context "missing metadata" do
    let(:template_id) { 'invalid-no-metadata' }

    it "raises an error when metadata is missing" do
      template.valid?
      expect(template.errors).not_to be_empty
      expect(template).to have_error(:metadata, 'has not been saved')
    end
  end

  context "invalid metadata" do
    let(:template_id) { 'invalid-metadata' }

    it "raises an error when metadata is invalid" do
      template.valid?
      expect(template.errors).not_to be_empty
      expect(template).to have_error(:metadata, 'is not valid')
    end
  end
end
