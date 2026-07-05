from .cli import build_parser


def main() -> int:
    build_parser().parse_args()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
