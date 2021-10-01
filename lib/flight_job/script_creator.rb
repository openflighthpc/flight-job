#==============================================================================
# Copyright (C) 2021-present Alces Flight Ltd.
#
# This file is part of Flight Job.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Job is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Job. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Job, please visit:
# https://github.com/openflighthpc/flight-job
#==============================================================================

require 'json'
require 'tty-prompt'
require 'tempfile'

module FlightJob
  # Creates and saves a script from the given ....
  class ScriptCreator

    def initialize(id:, answers:, notes:, template:)
      @answers = answers
      @id = id
      @notes = notes
      @template = template
    end

    def call
      opts = ( @id ? { id: @id } : {} )
      script = Script.new(
        template_id: @template.id,
        script_name: @template.script_template_name,
        answers: @answers,
        notes: @notes,
        **opts
      )

      script.tags = @template.tags
      script.render_and_save
      script
    end
  end
end
