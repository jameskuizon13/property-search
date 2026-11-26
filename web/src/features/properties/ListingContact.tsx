import { formatOpenHome, statusLabels } from './format'
import type { Agent, Inspection, PropertyStatus } from './types'

const card = 'rounded-lg border border-slate-200 bg-white p-4'
const primaryLink =
  'block rounded-md bg-indigo-600 px-4 py-2 text-center text-sm font-medium text-white hover:bg-indigo-500'
const secondaryLink =
  'block rounded-md border border-slate-300 bg-white px-4 py-2 text-center text-sm font-medium text-slate-700 hover:bg-slate-50'

function initials(name: string) {
  return name
    .split(/\s+/)
    .map((part) => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

/** "0491 570 157" → "tel:+61491570157": the country code lets it dial from overseas too. */
function telHref(phone: string) {
  const digits = phone.replace(/[^\d+]/g, '')
  return `tel:${digits.startsWith('0') ? `+61${digits.slice(1)}` : digits}`
}

type AgentProps = {
  agent: Agent | null
  /** "12 Smith St, Fitzroy VIC 3065", for the email's subject. */
  listing: string
  loading: boolean
}

/**
 * Who to ask about the listing: a call link and an email link with the
 * listing in the subject. The app sends nothing itself; the phone or mail app
 * does (see the property-detail doc for why there is no enquiry form).
 */
export function AgentCard({ agent, listing, loading }: AgentProps) {
  return (
    <section aria-labelledby="agent-heading" className={card}>
      <h2 id="agent-heading" className="mb-3 font-semibold">
        Contact the agent
      </h2>
      {loading ? (
        <p className="text-sm text-slate-500">Loading agent…</p>
      ) : !agent ? (
        <p className="text-sm text-slate-600">No agent is listed for this property yet.</p>
      ) : (
        <>
          <div className="flex items-center gap-3">
            <span
              aria-hidden="true"
              className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-indigo-100 font-semibold text-indigo-800"
            >
              {initials(agent.name)}
            </span>
            <div className="min-w-0">
              <p className="font-medium text-slate-900">{agent.name}</p>
              <p className="text-sm text-slate-600">{agent.agency}</p>
            </div>
          </div>
          <div className="mt-4 space-y-2">
            <a href={telHref(agent.phone)} className={primaryLink}>
              Call {agent.phone}
            </a>
            <a
              href={`mailto:${agent.email}?subject=${encodeURIComponent(`Enquiry about ${listing}`)}`}
              className={secondaryLink}
            >
              Email {agent.name.split(' ')[0]}
            </a>
          </div>
        </>
      )}
    </section>
  )
}

type OpenHomesProps = {
  inspections: Inspection[]
  timeZone: string
  status: PropertyStatus
  loading: boolean
}

/** Upcoming open homes, in the listing's local time (with its zone when that isn't the viewer's). */
export function OpenHomes({ inspections, timeZone, status, loading }: OpenHomesProps) {
  return (
    <section aria-labelledby="open-homes-heading" className={card}>
      <h2 id="open-homes-heading" className="mb-3 font-semibold">
        Open homes
      </h2>
      {loading ? (
        <p className="text-sm text-slate-500">Loading open homes…</p>
      ) : status === 'for_sale' && inspections.length > 0 ? (
        <ul className="space-y-2 text-sm">
          {inspections.map((inspection) => {
            const { day, time } = formatOpenHome(inspection, timeZone)
            return (
              <li key={inspection.id} className="flex flex-wrap justify-between gap-x-3">
                <time dateTime={inspection.startsAt} className="font-medium text-slate-900">
                  {day}
                </time>
                <span className="text-slate-700">{time}</span>
              </li>
            )
          })}
        </ul>
      ) : status === 'for_sale' ? (
        <p className="text-sm text-slate-600">
          No open homes are scheduled. Contact the agent to arrange a private inspection.
        </p>
      ) : (
        <p className="text-sm text-slate-600">
          No open homes: this property is {statusLabels[status].toLowerCase()}.
        </p>
      )}
    </section>
  )
}
