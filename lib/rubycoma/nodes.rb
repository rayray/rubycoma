module Nodes
  class Inline
    :normal
    :emphasized
    :strong
    :strikethrough
    :code_span
    :link
    :image

    attr_accessor :style
    attr_accessor :content

    def initialize(style, content)
      @style = style
      @content = content
      @attributes = Hash.new
    end

    def prettyprint(tab = 0)
      puts "\t" * tab + '{'
      puts "\t" * (1+tab) + "style: #{style}"
      puts "\t" * (1+tab) + "content: #{content}"
      puts "\t" * (1+tab) + 'attributes: {'
      @attributes.each { |key, value|
        puts "\t" * (2+tab) + "#{key} : #{value}"
      }
      puts "\t" * (1+tab) + '}'
      puts "\t" * tab + '}'
    end
  end

  class Block
    attr_accessor :parent
    attr_accessor :open

    def initialize
      @parent = nil
      @open = true
    end

    def type
      self.class.name
    end

    def to_s(indent = 0)
      str =  ' ' * (indent) << "{\n"
      str << ' ' * (2+indent) << "class: #{self.class.name}\n"

      self.instance_variables.each { |v|

      }
      # if @info.length > 0
      #   str << ' ' * (2+indent) << "info: {\n"
      #   @info.each { |key, value|
      #     str << ' ' * (4+indent) << "#{key} : #{value}\n"
      #   }
      #   str << ' ' * (2+indent) << "}\n"
      # end
      #
      # if @children.count > 0
      #   str << ' ' * (2+indent) << "children: [\n"
      #   @children.each { |block|
      #     str << block.to_s(2+indent)
      #   }
      #   str << ' ' * (2+indent) << "]\n"
      # end
      #
      # if @lines.count > 0
      #   str << ' ' * (2+indent) << "lines: [\n"
      #   @lines.each { |line|
      #     str << ' ' * (4+indent) << '"' << line << "\"\n"
      #   }
      #   str << ' ' * (2+indent) << "]\n"
      # end

      str << ' ' * indent << "}\n"
      str
    end

    def accepts_lines?
      false
    end

    def can_contain?(block)
      false
    end

  end

  class Leaf < Block
    attr_accessor :strings
    attr_accessor :inlines

    def initialize
      super
      @strings = Array.new
      @inlines = Array.new
    end

    def accepts_lines?
      true
    end

    def can_contain?(block)
      false
    end
  end

  class Paragraph < Leaf; end
  class HTML < Leaf; end
  class Code < Leaf
    attr_accessor :is_fenced
    attr_accessor :fence_character
    attr_accessor :fence_length
    attr_accessor :offset

    def initialize(fenced = false, char = '', length = 0, offset = 0)
      super()
      @is_fenced, @fence_character, @fence_length, @offset = fenced, char, length, offset
    end
  end

  class HorizontalRule < Leaf; def accepts_lines?; false; end; end
  class Header < Leaf
    attr_accessor :level
    def initialize(l)
      super()
      @level = l
    end
    def accepts_lines?; false; end
  end


  class Container < Block
    attr_reader :children

    def initialize
      super()
      @children = Array.new
    end

    def add_child(new_block)
      new_block.parent = self
      @children.push(new_block)
    end

    def remove_child(block_to_delete)
      @children.delete(block_to_delete)
    end

    def can_contain?(block)
      block.class != ListItem
    end
  end

  class Document < Container; end
  class BlockQuote < Container; end

  class List < Container
    attr_accessor :is_ordered
    attr_accessor :is_tight
    attr_accessor :marker_character
    attr_accessor :start
    attr_accessor :delimiter
    attr_accessor :marker_offset
    attr_accessor :padding

    def can_contain?(block); block.class == ListItem; end;
    def initialize
      super()
      @is_ordered = false
      @marker_character = ''
      @start = -1
      @is_tight = true
    end

    def matches?(l)
      @is_ordered == l.is_ordered && @delimiter == l.delimiter && @marker_character == l.marker_character
    end

    def copy_properties(l)
      @is_ordered = l.is_ordered
      @is_tight = l.is_tight
      @marker_character = l.marker_character
      @start = l.start
      @delimiter = l.delimiter
      @marker_offset = l.marker_offset
      @padding = l.padding
    end
  end

  #inheritance abuse!
  class ListItem < List
    def can_contain?(block)
      block.class != ListItem
    end
  end
end
