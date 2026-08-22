#!/usr/bin/env python3
"""Compile the reviewed six-chapter Field Survival Guide into app JSON."""

from __future__ import annotations

import argparse
import json
import pathlib
import re


CHAPTERS = {
    "FIRE": ("fire", "Build warmth, cooking heat, and a rescue signal", "flame.fill", "fire"),
    "WATER": ("water", "Find, collect, and make water safer", "drop.fill", "water"),
    "SHELTER": ("shelter", "Protect yourself from exposure", "tent.fill", "earth"),
    "FIRST AID": ("first_aid", "Control immediate threats until help arrives", "cross.case.fill", "rescue"),
    "NAVIGATION": ("navigation", "Stay oriented and help rescuers find you", "location.north.fill", "sky"),
    "FOOD": ("food", "Protect energy and prepare food safely", "fork.knife", "wildlife"),
}

SKILL_IDS = {
    "fire": ["basic_fire", "wet_conditions", "bow_drill", "extinguish"],
    "water": ["find", "collect", "boil", "filter", "rainwater", "solar_still"],
    "shelter": ["site", "tarp", "debris_hut", "desert", "rainforest", "mountain"],
    "first_aid": ["bleeding", "wound", "burn", "fracture", "heat_exhaustion", "heat_stroke", "hypothermia", "rehydration"],
    "navigation": ["lost", "map_compass", "terrain", "polaris", "rescue_signal"],
    "food": ["efficient", "wild_plants", "fishing", "prepare_fish", "wild_game", "field_cooking"],
}


def visual(asset_id: str, filename: str, title: str, caption: str, alt: str, tags: list[str], priority: str = "high") -> dict:
    return {
        "id": asset_id,
        "imageName": asset_id,
        "sourceFilename": filename,
        "title": title,
        "caption": caption,
        "altText": alt,
        "searchTags": tags,
        "priority": priority,
    }


VISUALS = [
    visual("fire_basic_build", "regular_fire_camp.PNG", "Basic Fire Build", "Gather all fuel first. Start with tinder and small kindling, then add larger fuel only after the fire is established.", "Four-step guide showing tinder, kindling and fuel, a teepee fire structure, ignition, and gradual fuel addition.", ["fire", "tinder", "kindling", "fuel", "teepee"]),
    visual("fire_wet_conditions", "make_fire_in_wet_condition.PNG", "Fire in Wet Conditions", "Find protected dry material, split wood to expose the dry center, prepare fine tinder, and build heat from small fuel upward.", "Wet-weather fire guide showing dry fuel selection, split wood, fine tinder preparation, and gradual fire building.", ["wet fire", "rain", "dry wood", "split wood", "kindling"]),
    visual("fire_bow_drill", "bow_drill_start_fire.PNG", "Bow-Drill Fire", "Keep the spindle vertical, use smooth full-arm strokes, build a smoking ember, then transfer it carefully to prepared tinder.", "Detailed bow-drill diagram showing components, posture, ember creation, transfer, and tinder ignition.", ["bow drill", "friction fire", "ember", "tinder"]),
    visual("water_find_terrain", "locate_water.PNG", "Find Water in the Landscape", "Search known sources first, then follow drainage and concentrated green vegetation toward likely water.", "Terrain guide showing likely water locations in valleys, drainage channels, vegetation, rain, snow and ice.", ["find water", "drainage", "valley", "vegetation", "rain"]),
    visual("water_treatment", "purify_water.PNG", "Treat Water", "Let sediment settle, prefilter cloudy water, then boil or use an appropriate wilderness treatment method.", "Water-treatment guide showing settling, prefiltering, boiling and keeping treated water clean.", ["boil water", "filter water", "purify", "treatment", "pathogens"]),
    visual("water_solar_still", "solar_still_gather_water.png", "Solar Still", "Use a solar still only as a supplemental source where sun, plastic, moist ground, and a container are available.", "Solar-still diagram showing a sealed pit, center container, plastic sheet, weighted low point and condensation drip.", ["solar still", "condensation", "plastic sheet", "water"], "medium"),
    visual("shelter_terrain_comparison", "terrain_shelters.png", "Shelter by Terrain", "Choose dry, protected, draining ground and adapt shelter priorities to desert, rainforest, or mountain conditions.", "Terrain comparison showing shelter priorities for desert shade, rainforest drainage and mountain wind protection.", ["shelter site", "desert", "rainforest", "mountain", "drainage"]),
    visual("shelter_tarp_lean_to", "tarp.PNG", "Quick Tarp Shelter", "Anchor a ridgeline, angle the tarp for runoff, lower the windward side, and insulate yourself from the ground.", "Tarp shelter guide showing ridgeline, anchors, rain angle, wind protection and ground insulation.", ["tarp", "ridgeline", "lean-to", "rain shelter"]),
    visual("shelter_debris_hut", "debris_shelter.png", "Debris Hut", "Build a body-sized frame, cover it with a thick dry insulating layer, and make a deep dry bed.", "Debris-hut guide showing ridgepole, ribs, lattice, thick debris insulation, bed and small entrance.", ["debris hut", "ridgepole", "leaves", "insulation"]),
    visual("first_aid_commercial_tourniquet", "Commercial_tourniquet.png", "Commercial Tourniquet", "For life-threatening arm or leg bleeding: place, tighten, twist until bleeding stops, secure the windlass, and record the time.", "Four-step commercial tourniquet guide showing placement, tightening, windlass use, securing and time recording.", ["tourniquet", "severe bleeding", "hemorrhage", "windlass"], "critical"),
    visual("first_aid_improvised_tourniquet", "Primitive_tourniquet.png", "Improvised Tourniquet", "Use an improvised tourniquet only when life-threatening limb bleeding cannot be controlled and a commercial device is unavailable.", "Improvised tourniquet guide showing a broad band, windlass tightening, securing and time recording.", ["improvised tourniquet", "bleeding", "windlass"], "secondary"),
    visual("first_aid_improvised_splint", "Improvise_splint.png", "Improvised Fracture Splint", "Support the limb in the position found, pad rigid supports, secure above and below the injury, and recheck circulation.", "Three-step improvised splint guide showing circulation assessment, padded supports, securing and circulation recheck.", ["fracture", "splint", "broken bone", "immobilize"], "critical"),
    visual("first_aid_heat_cooling", "Heat_relief.png", "Rapid Cooling for Heat Emergency", "Move to shade, begin rapid cooling, monitor continuously, and arrange emergency help.", "Heat emergency guide showing shade, immersion, water plus airflow, wet-cloth cooling and monitoring.", ["heat stroke", "heat emergency", "cooling", "immersion", "shade"], "critical"),
    visual("first_aid_hypothermia_wrap", "Primitive_hyperthermia_wrap.png", "Primitive Hypothermia Wrap", "Protect from wind and rain, replace wet layers, insulate from the ground, wrap the person, and warm the torso.", "Five-step hypothermia wrap guide showing shelter, dry clothing, ground insulation, wrapping and torso warming.", ["hypothermia", "cold", "insulation", "wet clothing", "warming"], "critical"),
    visual("navigation_map_compass", "Campass_navigation.png", "Map and Compass: Orient and Take a Bearing", "Orient the map, align the compass with your route, account for declination where needed, then follow the bearing toward a visible landmark.", "Four-panel map-and-compass guide showing orientation, placement, alignment, declination and following a bearing.", ["map", "compass", "bearing", "declination", "orientation"]),
    visual("navigation_contour_lines", "Contour_line.png", "How to Read Contour Lines", "Close contour lines indicate steep ground; wider spacing indicates gentler slopes. Compare map shapes with the terrain around you.", "Topographic comparison showing steep and gentle slopes, ridge, valley, stream and contour intervals.", ["contour lines", "topographic map", "terrain", "ridge", "valley"]),
    visual("navigation_polaris", "Navigate_northern.png", "Northern Hemisphere Night Navigation", "Find Merak and Dubhe in the Big Dipper, extend their line about five times their separation, and locate Polaris to identify approximate north.", "Night-navigation diagram showing the Big Dipper, pointer stars, Polaris, Little Dipper and direction north.", ["Polaris", "North Star", "Big Dipper", "night navigation"]),
    visual("navigation_rescue_signals", "Rescue_signal.png", "Signal for Rescue", "Stay visible and combine sound, reflected light, bright ground signals, and electronic distress devices when available.", "Rescue signaling illustration showing whistle, mirror, bright marker, personal locator beacon and visible camp.", ["rescue", "signal", "whistle", "mirror", "PLB"]),
    visual("food_prepare_fish", "Cook_fish.png", "Clean and Cook a Fish in the Wild", "Keep raw and cooked areas separate, remove the internal organs, keep the flesh clean, and cook thoroughly.", "Five-step field fish guide showing cleaning, gutting, organ removal, cooking and checking doneness.", ["fish", "clean fish", "gut fish", "cook fish", "food safety"]),
]

PLACEMENTS = {
    "fire.basic_fire": [("fire_basic_build", "primary")],
    "fire.wet_conditions": [("fire_wet_conditions", "primary")],
    "fire.bow_drill": [("fire_bow_drill", "primary")],
    "water.find": [("water_find_terrain", "primary")],
    "water.boil": [("water_treatment", "primary")],
    "water.filter": [("water_treatment", "related")],
    "water.solar_still": [("water_solar_still", "primary")],
    "shelter.site": [("shelter_terrain_comparison", "primary")],
    "shelter.tarp": [("shelter_tarp_lean_to", "primary")],
    "shelter.debris_hut": [("shelter_debris_hut", "primary")],
    "shelter.desert": [("shelter_terrain_comparison", "related")],
    "shelter.rainforest": [("shelter_terrain_comparison", "related")],
    "shelter.mountain": [("shelter_terrain_comparison", "related")],
    "first_aid.bleeding": [("first_aid_commercial_tourniquet", "primary"), ("first_aid_improvised_tourniquet", "secondary")],
    "first_aid.fracture": [("first_aid_improvised_splint", "primary")],
    "first_aid.heat_exhaustion": [("first_aid_heat_cooling", "related")],
    "first_aid.heat_stroke": [("first_aid_heat_cooling", "primary")],
    "first_aid.hypothermia": [("first_aid_hypothermia_wrap", "primary")],
    "navigation.map_compass": [("navigation_map_compass", "primary")],
    "navigation.terrain": [("navigation_contour_lines", "primary")],
    "navigation.polaris": [("navigation_polaris", "primary")],
    "navigation.rescue_signal": [("navigation_rescue_signals", "primary")],
    "food.prepare_fish": [("food_prepare_fish", "primary")],
    "food.field_cooking": [("food_prepare_fish", "related")],
}

ALIASES = {
    "fire.wet_conditions": ["wet fire", "fire in rain"],
    "water.boil": ["purify water", "make water safe"],
    "water.filter": ["water purifier"],
    "first_aid.bleeding": ["stop bleeding", "hemorrhage", "tourniquet"],
    "first_aid.fracture": ["broken bone", "splint"],
    "first_aid.heat_stroke": ["heat emergency", "overheating"],
    "first_aid.hypothermia": ["cold person", "rewarming"],
    "navigation.map_compass": ["take a bearing", "orient map"],
    "navigation.polaris": ["north at night", "north star", "big dipper"],
    "navigation.rescue_signal": ["get rescued", "emergency beacon"],
}

RELATED = {
    "fire.basic_fire": ["fire.wet_conditions", "fire.bow_drill"],
    "fire.wet_conditions": ["fire.basic_fire"],
    "water.boil": ["water.filter", "water.collect"],
    "water.filter": ["water.boil", "water.collect"],
    "shelter.site": ["shelter.tarp", "shelter.debris_hut"],
    "first_aid.heat_exhaustion": ["first_aid.heat_stroke", "first_aid.rehydration"],
    "first_aid.heat_stroke": ["first_aid.heat_exhaustion"],
    "navigation.map_compass": ["navigation.terrain"],
    "navigation.terrain": ["navigation.map_compass"],
    "food.prepare_fish": ["food.fishing", "food.field_cooking"],
    "food.field_cooking": ["food.prepare_fish"],
}


def section_kind(heading: str | None, content: str) -> str:
    value = (heading or "").lower()
    if any(term in value for term in ("field tip", "key skill", "remember", "field rule", "field skill", "field use")):
        return "callout"
    if value in {"steps", "actions"}:
        return "steps"
    nonempty = [line for line in content.splitlines() if line.strip()]
    if nonempty and all(line.lstrip().startswith("-") for line in nonempty):
        return "bullets"
    return "text"


def parse_sections(lines: list[str]) -> list[dict]:
    sections: list[dict] = []
    heading: str | None = None
    body: list[str] = []

    def flush() -> None:
        content = "\n".join(body).strip().strip("-").strip()
        if content:
            sections.append({"heading": heading, "kind": section_kind(heading, content), "content": content})

    for line in lines:
        match = re.match(r"^###\s+(.+)$", line)
        if match:
            flush()
            heading = match.group(1).strip()
            body = []
        elif line.strip() != "---":
            body.append(line.rstrip())
    flush()
    return sections


def first_plain_text(sections: list[dict], fallback: str) -> str:
    for section in sections:
        text = re.sub(r"[*_`>#-]", "", section["content"])
        text = re.sub(r"\s+", " ", text).strip()
        text = re.sub(r"^\d+\.\s*", "", text)
        if text:
            sentence = re.split(r"(?<=[.!?])\s+", text)[0]
            return sentence[:180]
    return fallback


def build(source: pathlib.Path) -> dict:
    lines = source.read_text(encoding="utf-8").splitlines()
    chapter_matches = [i for i, line in enumerate(lines) if re.match(r"^# CHAPTER \d+ — ", line)]
    if len(chapter_matches) != 6:
        raise ValueError(f"expected 6 chapters, found {len(chapter_matches)}")
    chapters = []
    for chapter_offset, start in enumerate(chapter_matches):
        end = chapter_matches[chapter_offset + 1] if chapter_offset + 1 < len(chapter_matches) else next(
            (i for i in range(start + 1, len(lines)) if lines[i] == "# SURVIVAL PRIORITY CARD"), len(lines)
        )
        match = re.match(r"^# CHAPTER (\d+) — (.+)$", lines[start])
        assert match
        number, title = int(match.group(1)), match.group(2).strip()
        chapter_id, purpose, symbol, theme = CHAPTERS[title]
        skill_starts = [i for i in range(start + 1, end) if re.match(r"^## Skill \d+: ", lines[i])]
        expected_ids = SKILL_IDS[chapter_id]
        if len(skill_starts) != len(expected_ids):
            raise ValueError(f"{chapter_id}: expected {len(expected_ids)} skills, found {len(skill_starts)}")
        skills = []
        for offset, skill_start in enumerate(skill_starts):
            skill_end = skill_starts[offset + 1] if offset + 1 < len(skill_starts) else end
            skill_match = re.match(r"^## Skill (\d+): (.+)$", lines[skill_start])
            assert skill_match
            order, skill_title = int(skill_match.group(1)), skill_match.group(2).strip()
            skill_id = f"{chapter_id}.{expected_ids[offset]}"
            raw = lines[skill_start + 1:skill_end]
            difficulty = None
            explicit_purpose = None
            cleaned = []
            for line in raw:
                difficulty_match = re.match(r"^\*\*Difficulty:\*\*\s*(.+)$", line)
                purpose_match = re.match(r"^\*\*Purpose:\*\*\s*(.+)$", line)
                if difficulty_match:
                    difficulty = difficulty_match.group(1).strip()
                elif purpose_match:
                    explicit_purpose = purpose_match.group(1).strip()
                else:
                    cleaned.append(line)
            sections = parse_sections(cleaned)
            placements = [{"assetID": asset_id, "role": role} for asset_id, role in PLACEMENTS.get(skill_id, [])]
            visual_tags = []
            for placement in placements:
                item = next(item for item in VISUALS if item["id"] == placement["assetID"])
                visual_tags.extend(item["searchTags"])
            skills.append({
                "id": skill_id,
                "order": order,
                "title": skill_title,
                "purpose": explicit_purpose or first_plain_text(sections, purpose),
                "difficulty": difficulty,
                "sections": sections,
                "aliases": ALIASES.get(skill_id, []),
                "tags": list(dict.fromkeys([chapter_id.replace("_", " "), skill_title.lower(), *visual_tags])),
                "relatedSkillIDs": RELATED.get(skill_id, []),
                "visuals": placements,
            })
        chapters.append({
            "id": chapter_id,
            "order": number,
            "title": title.title() if title != "FIRST AID" else "First Aid",
            "purpose": purpose,
            "symbol": symbol,
            "theme": theme,
            "skills": skills,
        })
    return {
        "schemaVersion": 1,
        "title": "Field Survival Guide",
        "subtitle": "Essential Wilderness Skills",
        "introduction": "Use this book to solve six immediate survival needs: Fire • Water • Shelter • First Aid • Navigation • Food. Each skill is written for quick field use.",
        "chapters": chapters,
        "visuals": VISUALS,
        "priorityCard": [
            {"title": "Life", "text": "Control severe bleeding and immediate danger."},
            {"title": "Shelter", "text": "Protect yourself from heat, cold, wind, and rain."},
            {"title": "Signal", "text": "Make rescuers able to find you."},
            {"title": "Water", "text": "Find, collect, and purify it."},
            {"title": "Fire", "text": "Create warmth, boiled water, cooking heat, and signal."},
            {"title": "Food", "text": "Maintain energy for longer survival."},
        ],
        "masterySkills": [
            "Make fire with a lighter, match, and ferro rod",
            "Filter and boil natural water",
            "Build a tarp shelter",
            "Stop severe bleeding",
            "Navigate with a map and compass",
            "Signal rescuers",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    result = build(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
