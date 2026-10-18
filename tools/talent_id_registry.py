#!/usr/bin/env python3
"""Resolve and validate class/era scoped talent IDs."""
from __future__ import annotations

import pathlib
import yaml


LAYOUT = (pathlib.Path(__file__).resolve().parents[1] / "data" /
          "talents" / "id-layout.yaml")


class TalentIdRegistry:
    def __init__(self, layout: dict):
        self.layout = layout
        self.base = int(layout["base"])
        self.era_stride = int(layout["eraStride"])
        self.class_stride = int(layout["classStride"])
        self.relative_limit = int(layout["relativeIdLimit"])
        self.eras = {str(k): int(v) for k, v in layout["eras"].items()}
        self.classes = {str(k): int(v) for k, v in layout["classes"].items()}
        self._validate_layout()

    @classmethod
    def load(cls, path: pathlib.Path = LAYOUT) -> "TalentIdRegistry":
        layout = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(layout)

    def _validate_layout(self) -> None:
        if self.class_stride < self.relative_limit:
            raise ValueError("classStride must contain the full relative ID pool")
        if (self.era_stride < max(self.classes.values()) * self.class_stride
                + self.relative_limit):
            raise ValueError("eraStride overlaps class subranges")
        if len(set(self.eras.values())) != len(self.eras):
            raise ValueError("era slots must be unique")
        if len(set(self.classes.values())) != len(self.classes):
            raise ValueError("class IDs must be unique")

    def final_id(self, era: str, class_id: int, relative_id: int) -> int:
        if era not in self.eras:
            raise ValueError(f"unknown era: {era}")
        if int(class_id) not in self.classes.values():
            raise ValueError(f"unknown class ID: {class_id}")
        relative_id = int(relative_id)
        if not 0 <= relative_id < self.relative_limit:
            raise ValueError(
                f"relative ID {relative_id} is outside [0,{self.relative_limit})")
        return (self.base + self.eras[era] * self.era_stride
                + int(class_id) * self.class_stride + relative_id)

def validate(path: pathlib.Path = LAYOUT) -> None:
    registry = TalentIdRegistry.load(path)
    for era in registry.eras:
        for class_id in registry.classes.values():
            first = registry.final_id(era, class_id, 0)
            last = registry.final_id(era, class_id,
                                     registry.relative_limit - 1)
            print(f"{era} class {class_id}: {first}-{last}")


if __name__ == "__main__":
    validate()
