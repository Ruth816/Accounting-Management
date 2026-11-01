'use client'

import { useMemo, useRef, useState } from 'react'

export type SearchOption = { value: string; label: string; group?: string | null }

// A dropdown you can type into (Ruth, 1 November): type a few letters of any
// part of the name and the matching options show. Only a listed option can
// be chosen; the chosen value is sent as `name`.
export function SearchSelect({
  name,
  options,
  defaultValue,
  placeholder = 'Type to search',
  onChange,
}: {
  name: string
  options: SearchOption[]
  defaultValue?: string | null
  placeholder?: string
  onChange?: (value: string) => void
}) {
  const [value, setValue] = useState(defaultValue ?? '')
  const [text, setText] = useState(options.find((o) => o.value === defaultValue)?.label ?? defaultValue ?? '')
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const listRef = useRef<HTMLUListElement>(null)

  const matches = useMemo(() => {
    const words = text.toLowerCase().split(/\s+/).filter(Boolean)
    const typing = text !== (options.find((o) => o.value === value)?.label ?? '')
    if (!typing || words.length === 0) return options
    return options.filter((o) => {
      const hay = `${o.value} ${o.label}`.toLowerCase()
      return words.every((w) => hay.includes(w))
    })
  }, [text, value, options])

  const choose = (o: SearchOption) => {
    setValue(o.value)
    onChange?.(o.value)
    setText(o.label)
    setOpen(false)
  }

  return (
    <div className="search-select">
      <input type="hidden" name={name} value={value} />
      <input
        value={text}
        placeholder={placeholder}
        role="combobox"
        aria-expanded={open}
        aria-autocomplete="list"
        autoComplete="off"
        onFocus={(e) => {
          setOpen(true)
          e.target.select()
        }}
        onBlur={() =>
          setTimeout(() => {
            setOpen(false)
            // Typed text that isn't an option goes back to the chosen one.
            setText(options.find((o) => o.value === value)?.label ?? '')
          }, 150)
        }
        onChange={(e) => {
          setText(e.target.value)
          setOpen(true)
          setActive(0)
          if (!e.target.value) {
            setValue('')
            onChange?.('')
          }
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') {
            e.preventDefault()
            setOpen(true)
            setActive((a) => Math.min(a + 1, matches.length - 1))
          } else if (e.key === 'ArrowUp') {
            e.preventDefault()
            setActive((a) => Math.max(a - 1, 0))
          } else if (e.key === 'Enter' && open && matches[active]) {
            e.preventDefault()
            choose(matches[active])
          } else if (e.key === 'Escape') {
            setOpen(false)
          }
        }}
      />
      {open && (
        <ul className="search-options" ref={listRef} role="listbox">
          {matches.length === 0 && <li className="muted">No match</li>}
          {matches.slice(0, 200).map((o, i) => (
            <li
              key={o.value}
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
              {o.group && <span className="muted small"> · {o.group}</span>}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
