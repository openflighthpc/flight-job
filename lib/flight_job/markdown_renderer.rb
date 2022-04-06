#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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

require 'tty-markdown'
require 'word_wrap'

module FlightJob
  MarkdownRenderer = Struct.new(:content, :width) do
    attr_reader :colors

    def initialize(*_)
      super
      self.width ||= TTY::Screen.width
      self.width = FlightJob.config.minimum_terminal_width if self.width < FlightJob.config.minimum_terminal_width
      @colors = 256 # Attempt to use 256-color initially
    end

    def wrap_markdown
      min_width = FlightJob.config.minimum_terminal_width
      parse_markdown.split("\n").map do |padded_line|
        # Finds the un-padded line and the padding width
        line = padded_line.sub(/^\s*/, '')
        pad_width = padded_line.length - line.length
        padding = ' ' * pad_width

        # Wraps the un-padded line, adjusting for the paddding
        wrapped_line = WordWrap.ww(line, min_width - pad_width).chomp

        # Pads the start and additional new line characters
        "#{padding}#{wrapped_line}".gsub("\n", "\n#{padding}")
      end.join("\n")
    end

    # def wrap_markdown
    #   parse_markdown
    # end

    ##
    # HACK: The "greatest_width" represents a terminal large enough to fit the
    # content without text wrapping. This (*roughly) corresponds with the width
    # of the longest line in the content.
    # * There are edge cases due to the content being padded and colourized
    #
    # As the content length must be equal or greater than its longest line; the
    # total length can be used as proxy. An additional terminal width is added
    # to handle (*most) of the edge cases.
    # * There still maybe a corner case when formatting a single paragraph
    def greatest_width
      content.length + width
    end

    def parse_markdown
      # We want the string "a paragraph\nacross multiple\nlines." to wrapped
      # according the width of the terminal not according to where there
      # happen to be newlines in the paragraph.  This is consistent with how
      # markdown is displayed when converted to HTML and displayed in a
      # browser.
      #
      # We do this by first converting the content to kramdown, which has the
      # side-effect of adjusting newlines in paragraphs according to the given
      # line width.
      #
      # Then we give the adjusted markdown to TTY::Markdown.  It will wrap the
      # text itself and do a bad job especially where links are introduced.
      # So the text produced by TTY::Markdown is adjusted in the
      # `wrap_markdown` method.
      min_width = FlightJob.config.minimum_terminal_width
      kramdown = Kramdown::Document.new(content, line_width: min_width).to_kramdown
      TTY::Markdown.parse(kramdown, colors: colors, width: width, indent: false)
    rescue
      if colors > 16
        @colors = 16
        retry       # Retry using 16-colors
      end
    end
  end
end
