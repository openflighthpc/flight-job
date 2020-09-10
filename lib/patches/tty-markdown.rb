#==============================================================================
# This patch has been ported from:
# https://github.com/piotrmurach/tty-markdown/blob/93f6fe9096f3096d65dd3e752d9d873fd0f7acd6/lib/tty/markdown/converter.rb
#
# But modified to fit in with:
# https://github.com/piotrmurach/tty-markdown/blob/v0.6.0/lib/tty/markdown/parser.rb
#
# The following license applies strictly to this file alone.
# See LICENSE.txt for the main software license.
#
# The MIT License (MIT)
#
# Copyright (c) 2018 Piotr Murach
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#==============================================================================

require 'tty-markdown'
require 'uri'

module TTYMarkdownConverterPatch
  def convert_a(el, opts)
    if URI.parse(el.attr["href"]).class == URI::MailTo
      el.attr["href"] = URI.parse(el.attr["href"]).to
    end

    if el.children.size == 1 && el.children[0].type == :text && el.children[0].value == el.attr["href"]

      if !el.attr["title"].nil? && !el.attr["title"].strip.empty?
        opts[:result] << "(#{el.attr["title"]}) "
      end
      opts[:result] << @pastel.decorate(el.attr["href"], *@theme[:link])

    elsif el.children.size > 0  && (el.children[0].type != :text || !el.children[0].value.strip.empty?)
      inner(el, opts)

      opts[:result] << " #{TTY::Markdown.symbols[:arrow]} "
      if el.attr["title"]
        opts[:result] << "(#{el.attr["title"]}) "
      end
      opts[:result] << @pastel.decorate(el.attr["href"], *@theme[:link])
    end
  end
end

TTY::Markdown::Parser.prepend TTYMarkdownConverterPatch
