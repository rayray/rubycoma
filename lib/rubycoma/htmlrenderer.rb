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

    def out(s)
      str = if s.instance_of? Array
              s.join('\n')
            elsif s.instance_of? String
              s
            else
              return
            end

      @buffer << if @disable_tags > 0
                   str.gsub(REGEX_HTMLTAG, '')
                 else
                   str
                 end
      @last_out = str
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
          case current.style
            when :code_inline
              out(create_tag('code') << current.content << create_tag('/code'))
            when :html_inline
              out(current.content)
            when :text
              out(current.content)
            when :softbreak
              out('\n')
            when :hardbreak
              out(create_tag('br', nil, true))
            when :emphasized
              tag = if walker.entering
                      'em'
                    else
                      '/em'
                    end
              out(create_tag(tag))
            when :strong
              tag = if walker.entering
                      'strong'
                    else
                      'strong'
                    end
              out(create_tag(tag))
            when :link
              if walker.entering
                attrs << ['href', current.destination]
                attrs << ['title', current.title] if current.title
                out(create_tag('a', attrs))
              else
                out(create_tag('/a'))
              end
            when :image
              if walker.entering
                if @disable_tags == 0
                  out('<img src="' << current.destination << '" alt="')
                end
                @disable_tags += 1
              else
                @disable_tags -= 1
                if @disable_tags == 0
                  if current.title
                    out('" title="' << current.title)
                  end
                  out('" />')
                end
              end
            else
              puts "Unknown inline type: #{current.style}"
          end

        elsif c <= Block
          case
            when c == HTML
              cr
              out(current.strings)
              cr
            when c == BlockQuote
                cr
                out(create_tag((walker.entering) ? 'blockquote' : '/blockquote', attrs))
                cr
            when c == Code
              info_string = current.info_string
              attrs << ['class', 'language-' << info_string] if info_string.length > 0
              cr
              out(create_tag('pre') << create_tag('code', attrs))
              out(current.strings)
              out(create_tag('/code') << create_tag('/pre'))
              cr
            when c == List
              tagname = current.is_ordered ? 'ol' : 'ul'
              if walker.entering
                start = current.start
                if start && start != 1
                  attrs << ['start', "#{start}"]
                end
                cr
                out(create_tag(tagname, attrs))
                cr
              else
                cr
                out(create_tag('/' << tagname))
                cr
              end
            when c == ListItem
              if walker.entering
                out(create_tag('li', attrs))
              else
                out(create_tag('/li'))
                cr
              end
            when c == Header
              tagname = 'h' << current.level
              if walker.entering
                cr
                out(create_tag(tagname, attrs))
              else
                out(create_tag('/' << tagname))
                cr
              end
            when c == HorizontalRule
              cr
              out(create_tag('hr', attrs, true))
              cr
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
            when c == Document
              #break
            else
              puts "Unknown node type: #{current.class}"
          end
        end
        current = walker.next
      end
      @buffer
    end
  end
end