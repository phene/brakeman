require 'set'
require 'brakeman/processors/alias_processor'
require 'brakeman/processors/lib/render_helper'

#Processes aliasing in templates.
#Handles calls to +render+.
class Brakeman::TemplateAliasProcessor < Brakeman::AliasProcessor
  include Brakeman::RenderHelper

  FORM_METHODS = Set[:form_for, :remote_form_for, :form_remote_for]

  def initialize tracker, template, called_from = nil
    super tracker
    @template = template
    @called_from = called_from
  end

  #Process template
  def process_template name, args
    if @called_from
      unless @called_from.grep(/Template:#{name}$/).empty?
        Brakeman.debug "Skipping circular render from #{@template[:name]} to #{name}"
        return
      end

      super name, args, @called_from + ["Template:#{@template[:name]}"]
    else
      super name, args, ["Template:#{@template[:name]}"]
    end
  end

  #Determine template name
  def template_name name
    unless name.to_s.include? "/"
      name = "#{@template[:name].to_s.match(/^(.*\/).*$/)[1]}#{name}"
    end
    name
  end

  #Looks for form methods and iterating over collections of Models
  def process_call_with_block exp
    process_default exp
    
    call = exp.block_call

    if call? call
      target = call.target
      method = call.method
      args = exp.block_args
      block = exp.block

      #Check for e.g. Model.find.each do ... end
      if method == :each and args and block and model = get_model_target(target)
        if node_type? args, :lasgn
          if model == target.target
            env[Sexp.new(:lvar, args.lhs)] = Sexp.new(:call, model, :new, Sexp.new(:arglist))
          else
            env[Sexp.new(:lvar, args.lhs)] = Sexp.new(:call, Sexp.new(:const, Brakeman::Tracker::UNKNOWN_MODEL), :new, Sexp.new(:arglist))
          end

          process block if sexp? block
        end
      elsif FORM_METHODS.include? method
        if node_type? args, :lasgn
          env[Sexp.new(:lvar, args.lhs)] = Sexp.new(:call, Sexp.new(:const, :FormBuilder), :new, Sexp.new(:arglist)) 

          process block if sexp? block
        end
      end
    end

    exp
  end

  alias process_iter process_call_with_block

  #Checks if +exp+ is a call to Model.all or Model.find*
  def get_model_target exp
    if call? exp
      target = exp.target

      if exp.method == :all or exp.method.to_s[0,4] == "find"
        models = Set.new @tracker.models.keys

        begin
          name = class_name target
          return target if models.include?(name)
        rescue StandardError
        end

      end

      return get_model_target(target)
    end

    false
  end

  #Ignore `<<` calls on template variables which are used by the templating
  #library (HAML, ERB, etc.)
  def find_push_target exp
    if sexp? exp
      if exp.node_type == :lvar and (exp.value == :_buf or exp.value == :_erbout)
        return nil
      elsif exp.node_type == :ivar and exp.value == :@output_buffer
        return nil
      elsif exp.node_type == :call and call? exp.target and
        exp.target.method == :_hamlout and exp.method == :buffer

        return nil
      end
    end

    super
  end
end
