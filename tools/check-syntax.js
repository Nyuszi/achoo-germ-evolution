// Quick syntax check of every .luau file without Roblox Studio.
// It rewrites the few Luau-only bits this project uses (+=, -=, *=, /=, ..=, continue)
// into plain Lua and parses the result.  npm run check
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const files = [];
(function walk(dir) {
	for (const f of fs.readdirSync(dir)) {
		const p = path.join(dir, f);
		if (fs.statSync(p).isDirectory()) walk(p);
		else if (p.endsWith(".luau")) files.push(p);
	}
})(path.join(__dirname, "..", "src"));

let bad = 0;
for (const file of files) {
	let src = fs.readFileSync(file, "utf8");
	src = src.replace(/^(\s*)([\w.\[\]"':]+)\s*(\+|-|\*|\/|\.\.)=\s*/gm, (_, ws, lhs, op) => `${ws}${lhs} = ${lhs} ${op} `);
	src = src.replace(/\bcontinue\b/g, "goto continue");
	try {
		luaparse.parse(src, { luaVersion: "5.3" });
	} catch (e) {
		bad++;
		console.log(`${path.relative(process.cwd(), file)}: ${e.message}`);
	}
}
console.log(`${files.length - bad}/${files.length} files parse`);
process.exit(bad ? 1 : 0);
