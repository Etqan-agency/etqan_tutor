import fs from "node:fs";
const [out, artifact] = process.argv.slice(2);
const page = fs.readFileSync("index2.src.html", "utf8").replace("__DATA__", () => fs.readFileSync("logos2.json", "utf8"));
fs.writeFileSync(artifact, page);
fs.writeFileSync(out + "/index.html", `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n</head>\n<body>\n${page}\n</body>\n</html>\n`);
