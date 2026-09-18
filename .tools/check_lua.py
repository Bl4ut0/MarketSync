import glob, re

def check_file(fname):
    with open(fname, "r", encoding="utf-8", errors="ignore") as f:
        src = f.read()

    # Clean multiline comments and strings
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.DOTALL)
    src = re.sub(r"--.*", "", src)
    src = re.sub(r'\[(=*)\[.*?\]\1\]', '""', src, flags=re.DOTALL)
    src = re.sub(r'"([^"\\]|\\.)*"', '""', src)
    src = re.sub(r"'([^'\\]|\\.)*'", "''", src)

    tokens = re.findall(r"\b(function|if|then|elseif|else|for|while|do|repeat|until|end)\b", src)
    
    stack = []
    for t in tokens:
        if t == "function":
            stack.append("function")
        elif t == "if":
            stack.append("if")
        elif t == "for" or t == "while":
            stack.append("loop")
        elif t == "do":
            if stack and stack[-1] == "loop":
                stack.pop()
                stack.append("do_loop")
            else:
                stack.append("do_block")
        elif t == "repeat":
            stack.append("repeat")
        elif t == "until":
            if stack and stack[-1] == "repeat":
                stack.pop()
            else:
                return False, f"Unexpected 'until', stack: {stack}"
        elif t == "end":
            if stack and stack[-1] in ("function", "if", "do_loop", "do_block"):
                stack.pop()
            else:
                return False, f"Unexpected 'end', stack: {stack}"
    if stack:
        return False, f"Unclosed blocks: {stack}"
    return True, "OK"

for f in sorted(glob.glob("MarketSync/*.lua")):
    ok, msg = check_file(f)
    print(f"{f}: {'PASS' if ok else 'FAIL: ' + msg}")
