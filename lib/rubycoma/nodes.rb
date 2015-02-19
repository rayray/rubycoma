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
      var_indent = indent + 2
      arr_indent = indent + 4
      str =  ' ' * indent << "{\n"
      str << ' ' * var_indent << "class: " << self.class.name << "\n"

      self.instance_variables.each { |var|
        next if var == :@parent
        value = instance_variable_get(var)

        if value.class == Array
          str << ' ' * var_indent << "#{var}: [\n"
          value.each { |obj|

            if obj.class <= Block
              str << obj.to_s(arr_indent)
            else
              str << ' ' * arr_indent << obj.to_s
            end
            str << "\n"
          }
          str << ' ' * var_indent << "]\n"
        else
          str << ' ' * var_indent << "#{var}: #{value}\n"
        end
      }

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
    attr_accessor :fence_offset
    attr_accessor :info_string

    def initialize(fenced = false, char = '', length = 0, offset = 0)
      super()
      @is_fenced, @fence_character, @fence_length, @fence_offset = fenced, char, length, offset
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
