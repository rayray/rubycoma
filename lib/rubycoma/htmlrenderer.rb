module RubyCoMa
  require_relative '../rubycoma/nodes'
  class HtmlRenderer
    include Nodes

    REGEX_HTMLTAG = /<[^>]*>/

    def initialize
      @buffer = ''
      @disable_tags = 0
      @last_out
    end

    def out(strings)
      if strings.to_a.empty?
        STDERR.puts "WARNING: strings was empty."
        return
      end

      s = strings.join('\n')
      @buffer << if @disable_tags > 0
                   s.gsub(REGEX_HTMLTAG, '')
                 else
                   s
                 end
      @last_out = s
    end

    def cr
      if @last_out == '\n'
        @buffer << '\n'
        @last_out = '\n'
      end
    end

    def create_tag(name, attrs = nil, selfclosing = false)
      result = '<' << name

      unless attrs.to_a.empty?
        attrs.each { |attrib|
          result << ' ' <<  attrib[0] << '="' << attrib[1] << '"'
        }
      end

      if selfclosing
        result << ' /'
      end
      result << '>'
      result
    end

    def render_block(block)
      walker = NodeWalker.new(block)
      attrs = []

      current = walker.next

      until current.nil?

        c = current.class

        if c == Inline
          case
            when current.style == :code_span
              out(create_tag('code') << current.strings.join('\n') << create_tag('/code'))
            when current.style == :html_span
              out(current.strings)
            else
              abort("Unknown inline type: #{current.style}")
          end

        elsif c <= Block
          case
            when c == HTML

            when c == Code

            when c == Paragraph
              grandparent = current.parent.parent
              unless grandparent && grandparent.class == List && grandparent.is_tight
                if walker.entering
                  cr
                  out(create_tag('p', attrs))
                else
                  out(create_tag('/p'))
                  cr
                end
              end
            else
              abort("Unknown node type: #{current.class}")
          end
        end
        current = walker.next
      end
      @buffer
    end
  end
end