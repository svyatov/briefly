# frozen_string_literal: true

# Facades that violate reflection parity on purpose. A guard that cannot fail is not a guard, so each
# assertion in `reflection_test.rb` and `rescue_from_test.rb` is also pointed at the fixture whose
# defect it exists to catch, and asserted to see the defect.

# Dispatch as `briefly` shipped it before reflection parity: one shared variadic proc per definition.
# It reports `arity -1`, points its `source_location` inside this file, and accepts any argument list —
# so a wrong-arity call raises inside `__call`, where a facade-wide handler swallows it.
class VariadicFacade < Briefly::Facade
  private

  def __define(defn)
    sc = singleton_class
    sc.send(:remove_method, defn.raw_name) if sc.private_method_defined?(defn.raw_name, false)
    sc.define_method(defn.raw_name, &defn.body)
    sc.send(:private, defn.raw_name)

    canonical = defn.canonical
    dispatch = proc { |*args, **kwargs, &blk| __call(canonical, *args, **kwargs, &blk) }
    defn.names.each do |name|
      sc.send(:remove_method, name) if @__public.include?(name)
      sc.define_method(name, &dispatch)
    end
  end
end

# The real dispatch, installed without the warning suppression `Candor.define` wraps it in. A second
# `configure` pass over the same shortcut then warns `method redefined` under `-w`.
class RedefiningFacade < Briefly::Facade
  private

  def __define(defn)
    sc = singleton_class
    sc.define_method(defn.raw_name, &defn.body)
    sc.send(:private, defn.raw_name)

    parameters = defn.memoized? ? [] : sc.instance_method(defn.raw_name).parameters
    dispatch = Candor::Signature.compile(
      parameters, name: defn.canonical, via: :__call, source_location: defn.source_location
    )
    defn.names.each { |name| sc.define_method(name, &dispatch) }
  end
end
