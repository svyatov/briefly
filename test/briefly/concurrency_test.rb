# frozen_string_literal: true

require "test_helper"

class ConcurrencyTest < BrieflyTest
  THREADS = 32

  def test_a_memoized_body_runs_once_under_contention
    lock = Mutex.new
    calls = 0
    facade = Briefly.define do
      shortcut(:slow) do
        lock.synchronize { calls += 1 }
        sleep 0.01
        :value
      end.memoize
    end

    results = race { facade.slow }

    assert_equal 1, calls
    assert_equal [:value], results.uniq
  end

  # A memoized body reading another uncomputed memoized shortcut re-enters the lock. With a plain
  # Mutex that is a `ThreadError: deadlock; recursive locking`.
  def test_a_memoized_body_may_call_another_memoized_shortcut
    inner_calls = 0
    outer_calls = 0
    facade = Briefly.define do
      shortcut(:inner) do
        inner_calls += 1
        :inner
      end.memoize
      shortcut(:outer) do
        outer_calls += 1
        [inner, :outer]
      end.memoize
    end

    assert_equal %i[inner outer], facade.outer

    # The nested value must survive the outer write; otherwise `inner` recomputes forever.
    facade.inner
    facade.outer

    assert_equal 1, inner_calls
    assert_equal 1, outer_calls
  end

  def test_nested_memoized_shortcuts_under_contention
    inner_calls = 0
    outer_calls = 0
    lock = Mutex.new
    facade = Briefly.define do
      shortcut(:inner) { lock.synchronize { inner_calls += 1 } }.memoize
      shortcut(:outer) do
        lock.synchronize { outer_calls += 1 }
        inner
      end.memoize
    end

    race { facade.outer }

    assert_equal 1, inner_calls
    assert_equal 1, outer_calls
  end

  # The behavioural test below cannot distinguish copy-on-write from an unsynchronized mutable Hash
  # on CRuby, because a reader never observes nil either way. Assert the invariant directly.
  def test_the_memo_store_is_always_an_immutable_snapshot
    facade = Briefly.define do
      shortcut(:value) { Object.new }.memoize
    end

    assert_predicate memos(facade), :frozen?
    facade.value

    assert_predicate memos(facade), :frozen?
    facade.briefly.clear_memos!

    assert_predicate memos(facade), :frozen?
  end

  def test_clearing_memos_concurrently_with_reads_never_tears
    facade = Briefly.define do
      shortcut(:value) { Object.new }.memoize
    end

    ready = Thread::Queue.new
    start = Thread::Queue.new
    readers = Array.new(4) do
      Thread.new do
        ready << true
        start.pop
        Array.new(500) do
          Thread.pass
          facade.value
        end
      end
    end
    clearer = Thread.new do
      ready << true
      start.pop
      500.times do
        facade.briefly.clear_memos!
        Thread.pass
      end
    end
    # Start every worker together; bounded reads avoid filling a queue while the clearer waits to run.
    5.times { ready.pop }
    5.times { start << true }
    clearer.value
    values = readers.flat_map(&:value)

    assert_equal 2000, values.size
    refute_includes values, nil
  end

  private

  def memos(facade) = facade.instance_variable_get(:@__memos)

  def race
    go = false
    threads = Array.new(THREADS) do
      Thread.new do
        Thread.pass until go
        yield
      end
    end
    go = true
    threads.map(&:value)
  end
end
