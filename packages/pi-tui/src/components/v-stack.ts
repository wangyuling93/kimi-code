import { Container, type RenderContext } from "../tui.ts";
import { allocateStackSizes, Stack, type StackChild, type StackOptions, visibleStackEntries } from "./stack.ts";

export class VStack extends Stack {
	protected readonly layoutType = "vstack" as const;

	constructor(children: StackChild[] = [], options: StackOptions = {}) {
		super(children, options);
	}

	override render(width: number, ctx?: RenderContext): string[] {
		const viewport = { width: Math.max(1, width), height: Number.MAX_SAFE_INTEGER };
		const entries = visibleStackEntries(this.entries, viewport);
		// Sizes depend on rendered heights, so measure first (cheap: components
		// cache their own output) and then render again with the context
		// positions so leaf components can register mouse hit regions.
		const measured = entries.map((entry) => entry.component.render(viewport.width));
		const sizes = allocateStackSizes(
			entries,
			measured.map((lines) => lines.length),
			undefined,
			this.gap,
		);
		const lines: string[] = [];
		let row = 0;
		for (let index = 0; index < entries.length; index++) {
			if (index > 0) {
				for (let gap = 0; gap < this.gap; gap++) lines.push("");
				row += this.gap;
			}
			const childCtx = ctx ? { row: ctx.row + row, col: ctx.col, regions: ctx.regions } : undefined;
			const childLines = childCtx ? entries[index]!.component.render(viewport.width, childCtx) : measured[index]!;
			if (childCtx && !(entries[index]!.component instanceof Container)) {
				childCtx.regions.push({
					component: entries[index]!.component,
					rowStart: childCtx.row,
					colStart: childCtx.col,
					rowEnd: childCtx.row + Math.min(childLines.length, sizes[index]!),
					colEnd: childCtx.col + viewport.width,
				});
			}
			const visibleChildLines = childLines.slice(0, sizes[index]);
			lines.push(...visibleChildLines);
			for (let padding = visibleChildLines.length; padding < sizes[index]!; padding++) lines.push("");
			row += sizes[index]!;
		}
		return lines;
	}
}

export type { StackChild, StackEntry, StackEntryOptions, StackOptions } from "./stack.ts";
