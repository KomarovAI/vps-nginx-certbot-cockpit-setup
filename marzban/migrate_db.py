from alembic.config import main as alembic_main

if __name__ == "__main__":
    alembic_main(["upgrade", "head"])
