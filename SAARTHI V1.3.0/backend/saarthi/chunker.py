from dataclasses import replace
from datetime import timedelta
from saarthi.Models import Task, Chunk
from saarthi.config import SchedulerConfig, DEFAULT_CONFIG


def compute_break(duration: timedelta, config: SchedulerConfig) -> timedelta:
    """
    Break scales with chunk size, capped at max_break_minutes.
    break = max(default_break, duration * break_ratio)
    """
    default = timedelta(minutes=config.default_break_minutes)
    scaled  = duration * config.break_ratio
    cap     = timedelta(minutes=config.max_break_minutes)
    return min(max(default, scaled), cap)


def chunk_task(task: Task, config: SchedulerConfig = DEFAULT_CONFIG) -> list[Chunk]:
    """
    Rules:
    - Non-flexible task → one Chunk (atomic, take-it-or-leave-it)
    - Flexible task → split by focus_limit
    - Orphan rule: if last piece < orphan_threshold * focus_limit, merge into previous
    """
    chunks = []

    # Non-flexible: single atomic chunk
    if not task.flexible:
        brk = compute_break(task.duration, config)
        chunks.append(Chunk(
            id=f"{task.id}_c0",
            parent_id=task.id,
            parent_name=task.name,
            index=0,
            duration=task.duration,
            deadline=task.deadline,
            is_final=True,
            break_after=brk,
        ))
        return chunks

    # Flexible: split by focus_limit
    remaining = task.duration
    index = 0

    while remaining > timedelta(0):
        piece = min(task.focus_limit, remaining)

        # Orphan rule: if this tiny last piece is too small, merge into previous chunk
        orphan_threshold = task.focus_limit * config.orphan_chunk_threshold
        if piece < orphan_threshold and chunks:
            # Add remaining time to the previous chunk's duration
            prev = chunks[-1]
            new_dur = prev.duration + piece
            new_brk = compute_break(new_dur, config)
            chunks[-1] = Chunk(
                id=prev.id,
                parent_id=prev.parent_id,
                parent_name=prev.parent_name,
                index=prev.index,
                duration=new_dur,
                deadline=prev.deadline,
                is_final=True,
                break_after=new_brk,
            )
            break

        brk = compute_break(piece, config)
        is_final = (remaining - piece) <= timedelta(0)

        chunks.append(Chunk(
            id=f"{task.id}_c{index}",
            parent_id=task.id,
            parent_name=task.name,
            index=index,
            duration=piece,
            deadline=task.deadline,
            is_final=is_final,
            break_after=brk,
        ))

        remaining -= piece
        index += 1

    # Mark the actual last chunk as final (handles edge cases)
    if chunks:
        chunks[-1] = replace(chunks[-1], is_final=True)

    return chunks
