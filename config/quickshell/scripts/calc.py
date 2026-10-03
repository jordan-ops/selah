#!/usr/bin/env python3
"""Launcher calculator: evaluate a plain-arithmetic expression safely.

argv[1] is the query (e.g. "18*0.21"). Only numbers and the operators
+ - * / % ^ ( ) are accepted — the AST whitelist below refuses names,
attributes, calls, imports and everything else, so this can never run
arbitrary code (no eval, no exec).

Prints one line (int, or a float trimmed to 10 significant digits) and
exits 0. Anything it refuses exits 1 with no stdout, which hides the
launcher's calc row instead of showing an error.
"""
import ast
import sys

MAX_EXPR = 60


def evaluate(node):
    if isinstance(node, ast.Constant) and type(node.value) in (int, float):
        return node.value
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        val = evaluate(node.operand)
        return val if isinstance(node.op, ast.UAdd) else -val
    if isinstance(node, ast.BinOp):
        a = evaluate(node.left)
        b = evaluate(node.right)
        op = node.op
        if isinstance(op, ast.Add):
            return a + b
        if isinstance(op, ast.Sub):
            return a - b
        if isinstance(op, ast.Mult):
            return a * b
        if isinstance(op, ast.Div):
            return a / b
        if isinstance(op, ast.Mod):
            return a % b
        if isinstance(op, ast.Pow):
            if abs(b) > 64 or abs(a) > 1e12:
                raise ValueError("exponent out of range")
            return a ** b
    raise ValueError("unsupported expression")


def main():
    if len(sys.argv) < 2:
        return 1
    expr = sys.argv[1].strip()
    if not expr or len(expr) > MAX_EXPR:
        return 1
    # calculator-style caret means POWER here; Python would read it as
    # bitwise XOR, which nobody expects from "2^10"
    expr = expr.replace("^", "**")
    try:
        value = evaluate(ast.parse(expr, mode="eval").body)
    except (ValueError, SyntaxError, ZeroDivisionError, OverflowError, MemoryError):
        return 1
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            return 1
        print("{:.10g}".format(value))
    else:
        print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
