/**
 * Starlight route middleware. The config lists the sidebar of both flavours;
 * here we keep only the groups of the flavour the current page belongs to,
 * and recompute the previous/next links so they never cross flavours.
 */
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import { DEFAULT_FLAVOUR, flavourOfPath, type Flavour } from './flavours';

type Entry = { type: 'link'; href: string; isCurrent: boolean; label: string } | { type: 'group'; entries: Entry[] };

function flavourOfEntry(entry: Entry): Flavour | undefined {
	if (entry.type === 'link') return flavourOfPath(entry.href);
	for (const child of entry.entries) {
		const f = flavourOfEntry(child);
		if (f) return f;
	}
	return undefined;
}

function links(entries: Entry[], out: Extract<Entry, { type: 'link' }>[] = []) {
	for (const e of entries) {
		if (e.type === 'link') out.push(e);
		else links(e.entries, out);
	}
	return out;
}

export const onRequest = defineRouteMiddleware((context) => {
	const route = context.locals.starlightRoute;
	const current = flavourOfPath(context.url.pathname) ?? DEFAULT_FLAVOUR;

	const sidebar = (route.sidebar as unknown as Entry[]).filter((e) => {
		const f = flavourOfEntry(e);
		return !f || f === current;
	});
	route.sidebar = sidebar as typeof route.sidebar;

	const flat = links(sidebar);
	const i = flat.findIndex((l) => l.isCurrent);
	route.pagination = {
		prev: (i > 0 ? flat[i - 1] : undefined) as typeof route.pagination.prev,
		next: (i >= 0 && i < flat.length - 1 ? flat[i + 1] : undefined) as typeof route.pagination.next,
	};
});
