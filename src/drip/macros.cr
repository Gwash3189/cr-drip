module Drip
  # Internal annotation used to record a `drip` or `rate_limit` declaration from the macro
  # to the `finished` hook that generates the wrapper method.
  annotation Declaration
  end

  # Declares that an instance method should be rate-limited using a sliding window.
  #
  # Supported options:
  # - `method`: Target method symbol (e.g. `:fetch_user` or first argument).
  # - `allow`: Maximum number of allowed requests in the window (default: 10).
  # - `per`: Sliding window duration (default: 1.second). Accepts native `Time::Span`,
  #   numbers (milliseconds), or strings (`"1s"`, `"500ms"`).
  # - `wait`: Maximum wait / throttle budget (default: 0.seconds). Accepts `Time::Span`, numbers, strings.
  # - `count`: Token cost per call (default: 1).
  # - `key`: Key expression:
  #   - A proc literal matching method arguments: `key: ->(id : String) { "user:#{id}" }`
  #   - A symbol of an instance method: `key: :rate_limit_key`
  #   - A static string: `key: "export_service"`
  #   - If omitted, defaults to `"ClassName#method_name(arg1, arg2)"`
  # - `fallback`: Fallback method symbol or proc invoked when rate limit is exceeded.
  # - `on_limited`: Optional callback symbol or proc invoked when rate limited.
  # - `on_throttled`: Optional callback symbol or proc invoked when throttled.
  #
  # ```
  # class ApiClient
  #   include Drip
  #
  #   drip :fetch_data,
  #     allow: 5,
  #     per: 1.second,
  #     wait: 200.milliseconds,
  #     key: ->(id : String) { "api:#{id}" },
  #     fallback: :rate_limited_fallback
  #
  #   def fetch_data(id : String) : String
  #     # ...
  #   end
  #
  #   def rate_limited_fallback(error : Drip::RateLimitError) : String
  #     "fallback"
  #   end
  # end
  # ```
  macro drip(*args, **options, &block)
    {% if options[:method] || (args.size > 0 && args[0].is_a?(SymbolLiteral)) %}
      {% method = options[:method] || args[0] %}
      {% key = options[:key] || (args.size > 1 && !args[1].is_a?(NamedTupleLiteral) ? args[1] : nil) %}
      {% allow = options[:allow] || 10 %}
      {% per = options[:per] != nil ? options[:per] : 1000 %}
      {% wait = options[:wait] != nil ? options[:wait] : 0 %}
      {% count = options[:count] || 1 %}
      {% fallback = options[:fallback] %}
      {% on_limited = options[:on_limited] %}
      {% on_throttled = options[:on_throttled] %}

      @[::Drip::Declaration(
        target: {{method}},
        key: {{key}},
        allow: {{allow}},
        per: {{per}},
        wait: {{wait}},
        count: {{count}},
        fallback: {{fallback}},
        on_limited: {{on_limited}},
        on_throttled: {{on_throttled}}
      )]
      private def __drip_declaration_{{method.id.stringify.gsub(/[^A-Za-z0-9_]/, "_").id}}
      end
    {% else %}
      {% if block %}
        {% if args.size > 0 && options.size > 0 %}
          ::Drip.__execute_drip({{args.splat}}, {{options.double_splat}}) {{block}}
        {% elsif args.size > 0 %}
          ::Drip.__execute_drip({{args.splat}}) {{block}}
        {% else %}
          ::Drip.__execute_drip({{options.double_splat}}) {{block}}
        {% end %}
      {% else %}
        {% if args.size > 0 && options.size > 0 %}
          ::Drip.__execute_drip({{args.splat}}, {{options.double_splat}})
        {% elsif args.size > 0 %}
          ::Drip.__execute_drip({{args.splat}})
        {% else %}
          ::Drip.__execute_drip({{options.double_splat}})
        {% end %}
      {% end %}
    {% end %}
  end

  # Alias for `drip`.
  macro rate_limit(*args, **options, &block)
    ::Drip.drip({{args.splat}}, {{options.double_splat}}) {% if block %}{{block}}{% end %}
  end

  macro included
    {% verbatim do %}
      macro finished
        {% for decl_method in @type.methods %}
          {% if decl_method.name.stringify.starts_with?("__drip_declaration_") %}
            {% decl = decl_method.annotation(::Drip::Declaration) %}
            {% if decl %}
              {% target = decl[:target] %}
              {% target_methods = @type.methods.select { |m| m.name == target.id } %}

              {% if target_methods.empty? %}
                {% raise "drip target `#{target.id}` was not found as an instance method on #{@type}" %}
              {% end %}

              {% for method in target_methods %}
                {% if method.abstract? %}
                  {% raise "cannot wrap abstract method #{@type}##{method.name}" %}
                {% end %}

                {% captured_block = method.block_arg && method.block_arg.internal_name.stringify != "" %}
                {% if captured_block && !method.block_arg.restriction %}
                  {% raise "cannot wrap #{@type}##{method.name}: give the captured block parameter a type or use an anonymous `&` block" %}
                {% end %}

                {% if method.visibility == :private %}private{% elsif method.visibility == :protected %}protected{% end %} def {{method.name}}(
                  {% for argument, index in method.args %}
                    {% if method.splat_index && index == method.splat_index %}
                      *{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %},
                    {% else %}
                      {% if argument.name.stringify != argument.internal_name.stringify %}{{argument.name}} {% end %}{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %}{% if argument.default_value %} = {{argument.default_value}}{% end %},
                    {% end %}
                  {% end %}
                  {% if method.double_splat %}**{{method.double_splat.internal_name}}{% if method.double_splat.restriction %} : {{method.double_splat.restriction}}{% end %},{% end %}
                  {% if captured_block %}&__drip_block : {{method.block_arg.restriction}}{% elsif method.accepts_block? %}&{% end %}
                )
                  {% if decl[:key].is_a?(ProcLiteral) %}
                    {% key_proc = decl[:key] %}
                    {% if key_proc.args.empty? %}
                      __drip_key = ({{key_proc}}).call.to_s
                    {% else %}
                      {% proc_call_args = [] of ASTNode %}
                      {% for parg in key_proc.args %}
                        {% match = method.args.find { |m_arg| m_arg.name.stringify == parg.name.stringify || m_arg.internal_name.stringify == parg.name.stringify } %}
                        {% if match %}
                          {% proc_call_args << match.internal_name %}
                        {% else %}
                          {% proc_call_args << parg.name %}
                        {% end %}
                      {% end %}
                      __drip_key = ({{key_proc}}).call({{proc_call_args.join(", ").id}}).to_s
                    {% end %}
                  {% elsif decl[:key].is_a?(SymbolLiteral) %}
                    {% key_sym = decl[:key].id %}
                    {% if method.args.empty? %}
                      __drip_key = self.{{key_sym}}.to_s
                    {% else %}
                      {% key_methods = @type.methods.select { |m| m.name == key_sym } %}
                      {% takes_args = key_methods.empty? || key_methods.any? { |m| m.args.size > 0 || m.splat_index || m.double_splat } %}
                      {% if takes_args %}
                        __drip_key = self.{{key_sym}}(
                          {% for arg in method.args %}
                            {{arg.internal_name}},
                          {% end %}
                        ).to_s
                      {% else %}
                        __drip_key = self.{{key_sym}}.to_s
                      {% end %}
                    {% end %}
                  {% elsif decl[:key] != nil %}
                    __drip_key = ({{decl[:key]}}).to_s
                  {% else %}
                    {% if method.args.empty? %}
                      __drip_key = {{@type.name.stringify}} + "#" + {{method.name.stringify}}
                    {% else %}
                      __drip_key = {{@type.name.stringify}} + "#" + {{method.name.stringify}} + ":" + {
                        {% for arg in method.args %}
                          {{arg.internal_name}},
                        {% end %}
                      }.to_s
                    {% end %}
                  {% end %}

                  {% if decl[:on_limited] %}
                    {% if decl[:on_limited].is_a?(SymbolLiteral) %}
                      __drip_on_limited = ->(__err : ::Drip::RateLimitError, __k : String) {
                        {% limited_methods = @type.methods.select { |m| m.name == decl[:on_limited].id } %}
                        {% takes_two = limited_methods.any? { |m| m.args.size >= 2 || m.splat_index || m.double_splat } %}
                        {% takes_one = limited_methods.any? { |m| m.args.size == 1 } %}
                        {% if takes_two %}
                          self.{{decl[:on_limited].id}}(__err, __k)
                        {% elsif takes_one %}
                          self.{{decl[:on_limited].id}}(__err)
                        {% else %}
                          self.{{decl[:on_limited].id}}
                        {% end %}
                        nil
                      }
                    {% else %}
                      __drip_on_limited = ->(__err : ::Drip::RateLimitError, __k : String) {
                        ({{decl[:on_limited]}}).call(__err, __k)
                        nil
                      }
                    {% end %}
                  {% else %}
                    __drip_on_limited = nil
                  {% end %}

                  {% if decl[:on_throttled] %}
                    {% if decl[:on_throttled].is_a?(SymbolLiteral) %}
                      __drip_on_throttled = ->(__wait : Time::Span, __k : String) {
                        {% throttled_methods = @type.methods.select { |m| m.name == decl[:on_throttled].id } %}
                        {% takes_two = throttled_methods.any? { |m| m.args.size >= 2 || m.splat_index || m.double_splat } %}
                        {% takes_one = throttled_methods.any? { |m| m.args.size == 1 } %}
                        {% if takes_two %}
                          self.{{decl[:on_throttled].id}}(__wait, __k)
                        {% elsif takes_one %}
                          self.{{decl[:on_throttled].id}}(__wait)
                        {% else %}
                          self.{{decl[:on_throttled].id}}
                        {% end %}
                        nil
                      }
                    {% else %}
                      __drip_on_throttled = ->(__wait : Time::Span, __k : String) {
                        ({{decl[:on_throttled]}}).call(__wait, __k)
                        nil
                      }
                    {% end %}
                  {% else %}
                    __drip_on_throttled = nil
                  {% end %}

                  begin
                    ::Drip.__execute_drip(
                      key: __drip_key,
                      allow: {{decl[:allow]}},
                      per: {{decl[:per]}},
                      wait: {{decl[:wait]}},
                      count: {{decl[:count]}},
                      on_limited: __drip_on_limited,
                      on_throttled: __drip_on_throttled
                    ) do
                      previous_def(
                        {% for argument, index in method.args %}
                          {% if method.splat_index && index == method.splat_index %}
                            {% if argument.internal_name.stringify != "" %}*{{argument.internal_name}},{% end %}
                          {% elsif !(method.splat_index && index > method.splat_index) %}
                            {{argument.internal_name}},
                          {% end %}
                        {% end %}
                        {% if method.double_splat %}**{{method.double_splat.internal_name}},{% end %}
                        {% for argument, index in method.args %}
                          {% if method.splat_index && index > method.splat_index %}
                            {{argument.name}}: {{argument.internal_name}},
                          {% end %}
                        {% end %}
                        {% if captured_block %}&__drip_block{% end %}
                      ){% if method.accepts_block? && !captured_block %} { |*__drip_block_args| yield *__drip_block_args }{% end %}
                    end
                  rescue __drip_err : ::Drip::RateLimitError
                    {% if decl[:fallback] %}
                      {% if decl[:fallback].is_a?(SymbolLiteral) %}
                        {% fallback_methods = @type.methods.select { |m| m.name == decl[:fallback].id } %}
                        {% takes_arg = fallback_methods.empty? || fallback_methods.any? { |m| m.args.size > 0 || m.splat_index || m.double_splat } %}
                        {% if takes_arg %}
                          self.{{decl[:fallback].id}}(__drip_err)
                        {% else %}
                          self.{{decl[:fallback].id}}
                        {% end %}
                      {% else %}
                        ({{decl[:fallback]}}).call(__drip_err)
                      {% end %}
                    {% else %}
                      raise __drip_err
                    {% end %}
                  end
                end
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      end
    {% end %}
  end
end
