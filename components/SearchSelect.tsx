'use client'

import { useEffect, useMemo, useRef, useState } from 'react'

export type SearchOption = { value: string; label: string; group?: string | null }

// A click-to-pick dropdown (Ruth, 12 November): click the field and the whole
// list opens, grouped under each QuickBooks account type, so an option can be
// picked without typing. The search box at the top of the list still narrows
// it by any part of the name (Ruth, 1 November). Only a listed option can be
// chosen; the chosen value is sent as `name`.
export function SearchSelect({
  name,
  options,
  defaultValue,
  placeholder = 'Click to choose',
  onChange,
}: {
  name: string
  options: SearchOption[]
  defaultValue?: string | null
  placeholder?: string
  onChange?: (value: string) => void
}) {
  const [value, setValue] = useState(defaultValue ?? '')
  const [text, setText] = useState('')
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const rootRef = useRef<HTMLDivElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const listRef = useRef<HTMLUListElement>(null)

  const chosenLabel = options.find((o) => o.value === value)?.label ?? value

  const matches = useMemo(() => {
    const words = text.toLowerCase().split(/\s+/).filter(Boolean)
    if (words.length === 0) return options
    return options.filter((o) => {
      const hay = `${o.value} ${o.label} ${o.group ?? ''}`.toLowerCase()
      return words.every((w) => hay.includes(w))
    })
  }, [text, options])

  const openList = () => {
    setText('')
    const i = options.findIndex((o) => o.value === value)
    setActive(i >= 0 ? i : 0)
    setOpen(true)
  }

  const choose = (o: SearchOption) => {
    setValue(o.value)
    onChange?.(o.value)
    setOpen(false)
    buttonRef.current?.focus()
  }

  // Close when clicking anywhere outside the dropdown.
  useEffect(() => {
    if (!open) return
    const close = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [open])

  // Keep the highlighted option (the chosen one when the list opens) in view.
  useEffect(() => {
    if (!open) return
    listRef.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)?.scrollIntoView({ block: 'nearest' })
  }, [open, active])

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      if (!open) openList()
      else setActive((a) => Math.min(a + 1, matches.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((a) => Math.max(a - 1, 0))
    } else if (e.key === 'Enter' && open && matches[active]) {
      e.preventDefault()
      choose(matches[active])
    } else if (e.key === 'Escape' && open) {
      e.preventDefault()
      setOpen(false)
      buttonRef.current?.focus()
    }
  }

  let lastGroup: string | null | undefined
  return (
    <div className="search-select" ref={rootRef} onKeyDown={onKeyDown}>
      <input type="hidden" name={name} value={value} />
      <button
        type="button"
        ref={buttonRef}
        className={`search-select-field${value ? '' : ' empty'}`}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => (open ? setOpen(false) : openList())}
      >
        <span>{value ? chosenLabel : placeholder}</span>
        <span className="search-select-chevron" aria-hidden>▾</span>
      </button>
      {open && (
        <div className="search-options">
          <input
            className="search-options-filter"
            value={text}
            placeholder="Type to search (optional)"
            autoComplete="off"
            aria-label="Search"
            onChange={(e) => {
              setText(e.target.value)
              setActive(0)
            }}
          />
          <ul ref={listRef} role="listbox">
            {matches.length === 0 && <li className="muted">No match</li>}
            {matches.map((o, i) => {
              const heading = o.group && o.group !== lastGroup ? o.group : null
              lastGroup = o.group
              return [
                heading && (
                  <li key={`h:${heading}`} className="search-options-group" role="presentation">
                    {heading}
                  </li>
                ),
                <li
                  key={o.value}
                  data-index={i}
                  role="option"
                  aria-selected={o.value === value}
                  className={i === active ? 'active' : undefined}
                  onMouseDown={(e) => {
                    e.preventDefault()
                    choose(o)
                  }}
                  onMouseEnter={() => setActive(i)}
                >
                  {o.label}
                </li>,
              ]
            })}
          </ul>
        </div>
      )}
    </div>
  )
}
