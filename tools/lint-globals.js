// Finds misspelled or undefined variables (globals that Roblox does not have) in every .luau file.
//   node tools/lint-globals.js
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const OK = new Set(("game workspace script Instance Vector3 Vector2 CFrame Color3 ColorSequence ColorSequenceKeypoint NumberSequence " +
	"NumberSequenceKeypoint NumberRange UDim UDim2 Enum math string table task buffer bit32 utf8 os pcall xpcall warn print " +
	"type typeof tostring tonumber pairs ipairs next select error assert setmetatable getmetatable rawget rawset rawequal " +
	"Random require coroutine debug TweenInfo Rect BrickColor PhysicalProperties RaycastParams OverlapParams Font DateTime tick time unpack").split(/\s+/));

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
	let ast;
	try {
		ast = luaparse.parse(src, { luaVersion: "5.3", scope: true, locations: true });
	} catch (e) {
		console.log(`${path.relative(process.cwd(), file)}: PARSE ${e.message}`);
		bad++;
		continue;
	}
	const seen = new Set();
	(function visit(node) {
		if (!node || typeof node !== "object") return;
		if (Array.isArray(node)) return node.forEach(visit);
		if (node.type === "Identifier" && node.isLocal === false && !OK.has(node.name)) {
			const key = node.name + ":" + node.loc.start.line;
			if (!seen.has(key)) {
				seen.add(key);
				console.log(`${path.relative(process.cwd(), file)}:${node.loc.start.line}: global '${node.name}'`);
				bad++;
			}
		}
		for (const k in node) if (k !== "loc" && k !== "range") visit(node[k]);
	})(ast);
}
console.log(bad ? `${bad} problems` : "no unknown globals");
process.exit(bad ? 1 : 0);
