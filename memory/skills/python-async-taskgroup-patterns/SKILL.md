---
name: python-async-taskgroup-patterns
description: "Master Python 3.11's asyncio.TaskGroup for robust structured concurrency with automatic exception aggregation and precise cancellation control using except* syntax."
---

# Python 3.11+ asyncio TaskGroup: Structured Concurrency and Cancellation Error Handling

- **Category:** `python-architecture`
- **Verification:** Passed isolated AST & runtime sandbox execution in GitHub Actions.

## Architectural Summary

This skill covers the modern structured concurrency pattern using asyncio.TaskGroup (Python 3.11+). Unlike asyncio.gather(), TaskGroup provides automatic cancellation of sibling tasks on failure and aggregates all exceptions into an ExceptionGroup. Learn to use the async with context manager, create_task method, and the except* syntax for granular exception handling. The pattern ensures reliable resource cleanup and predictable task lifecycle management.

## Verified Best Practices

- Always use asyncio.TaskGroup as a context manager (async with) to ensure automatic cleanup and exception aggregation
- Use task_group.create_task() to spawn concurrent tasks within the structured group
- Implement except* syntax to catch specific exception types from the aggregated ExceptionGroup
- Rely on TaskGroup's automatic cancellation behavior rather than manual task management
- Prefer TaskGroup over asyncio.gather() when you need structured concurrency and comprehensive error reporting
- Handle ExceptionGroup exceptions at the appropriate level to maintain proper error context

## Verified Reference Code

See runnable example at [verified_example.py](./examples/verified_example.py).

```python
import asyncio
import sys

async def test_taskgroup_success():
    """Test successful completion of all tasks in TaskGroup"""
    async def task(n):
        await asyncio.sleep(0.01)
        return n * 2

    async with asyncio.TaskGroup() as tg:
        t1 = tg.create_task(task(1))
        t2 = tg.create_task(task(2))
        t3 = tg.create_task(task(3))

    # All tasks completed successfully
    assert t1.result() == 2
    assert t2.result() == 4
    assert t3.result() == 6
    print("\u2713 TaskGroup success test passed")

async def test_taskgroup_cancellation():
    """Test that failing task cancels siblings and raises ExceptionGroup"""
    cancellation_occurred = False

    async def failing_task():
        raise ValueError("Intentional failure")

    async def cancellable_task():
        nonlocal cancellation_occurred
        try:
            await asyncio.sleep(1.0)  # Long running task
        except asyncio.CancelledError:
            cancellation_occurred = True
            raise

    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(failing_task())
            tg.create_task(cancellable_task())
    except* ValueError as eg:
        # Verify ExceptionGroup contains the ValueError
        assert len(eg.exceptions) == 1
        assert isinstance(eg.exceptions[0], ValueError)
        assert str(eg.exceptions[0]) == "Intentional failure"
    else:
        assert False, "Expected ExceptionGroup with ValueError"

    # Verify sibling task was cancelled
    assert cancellation_occurred, "Sibling task should have been cancelled"
    print("\u2713 TaskGroup cancellation test passed")

async def test_taskgroup_multiple_exceptions():
    """Test aggregation of multiple exceptions in ExceptionGroup"""
    async def failing_task_1():
        await asyncio.sleep(0.01)
        raise ValueError("First error")

    async def failing_task_2():
        await asyncio.sleep(0.01)
        raise TypeError("Second error")

    async def successful_task():
        await asyncio.sleep(0.02)
        return "success"

    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(failing_task_1())
            tg.create_task(failing_task_2())
            tg.create_task(successful_task())
    except* (ValueError, TypeError) as eg:
        # Should contain both exceptions
        assert len(eg.exceptions) == 2
        exception_types = {type(exc) for exc in eg.exceptions}
        assert ValueError in exception_types
        assert TypeError in exception_types
    else:
        assert False, "Expected ExceptionGroup with multiple exceptions"
    print("\u2713 TaskGroup multiple exceptions test passed")

async def test_taskgroup_except_star_syntax():
    """Test except* syntax for granular exception handling"""
    async def type_error_task():
        raise TypeError("Type error occurred")

    async def value_error_task():
        raise ValueError("Value error occurred")

    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(type_error_task())
            tg.create_task(value_error_task())
    except* TypeError as eg:
        # Handle only TypeError
        assert len(eg.exceptions) == 1
        assert isinstance(eg.exceptions[0], TypeError)
        print("  Handled TypeError separately")
    except* ValueError as eg:
        # Handle the ValueError separately so it does not propagate unhandled
        assert len(eg.exceptions) == 1
        assert isinstance(eg.exceptions[0], ValueError)
        print("  Handled ValueError separately")
    print("\u2713 except* syntax test passed")

async def main():
    print("Running asyncio.TaskGroup tests...")
    print()

    await test_taskgroup_success()
    await test_taskgroup_cancellation()
    await test_taskgroup_multiple_exceptions()
    await test_taskgroup_except_star_syntax()

    print()
    print("All tests passed! \u2713")

if __name__ == "__main__":
    if sys.version_info < (3, 11):
        print("This test requires Python 3.11+")
        sys.exit(1)
    asyncio.run(main())
```

## Sources

- <https://www.geeksforgeeks.org/python/python-taskgroups-with-asyncio/>
- <https://docs.python.org/3.11/library/asyncio-task.html>
- <https://www.stanza.dev/courses/python-concurrency/structured-concurrency/python-concurrency-task-groups>
- <https://salivity.github.io/python/article/python-3-11-task-groups-and-structured-concurrency>
- <https://universopython.com/en/blog/python-asyncio-taskgroup>
