"""Linux-runnable source contracts, not Swift compilation or rendered UI tests.
Run: python3 SwiftRecruitAppTests/home_calendar_polish_source_tests.py
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / "SwiftRecruitApp/Views/Home/HomeView.swift").read_text()
CALENDAR = (ROOT / "SwiftRecruitApp/Views/Calendar/RecruitCalendarView.swift").read_text()


def section(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


class HomeCalendarPolishSourceTests(unittest.TestCase):
    def test_undo_is_overlay_with_unconditional_scroll_clearance(self):
        self.assertNotIn(".safeAreaInset", HOME)
        self.assertIn(".overlay(alignment: .bottom) { undoOverlay }", HOME)
        self.assertIn(".contentMargins(.bottom, undoContentClearance, for: .scrollContent)", HOME)
        clearance = section(HOME, "private var undoContentClearance", "private var undoOverlay")
        self.assertNotIn("completed", clearance)
        overlay = section(HOME, "private var undoOverlay", "private var undoBarPlaceholder")
        self.assertIn(".allowsHitTesting(false)", overlay)
        self.assertNotIn("ignoresSafeArea", HOME)

    def test_empty_content_remains_refreshable(self):
        empty = section(HOME, "} else if hasItems == false {", "} else {")
        for token in ["ScrollView", ".scrollBounceBehavior(.always)", ".refreshable { await reload() }"]:
            self.assertIn(token, empty)

    def test_short_motion_respects_accessibility(self):
        self.assertEqual(HOME.count("withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2))"), 2)
        self.assertEqual(HOME.count(".animation(reduceMotion ? nil : .easeInOut(duration: 0.18)"), 2)
        self.assertIn(".transition(.opacity)", HOME)

    def test_each_completion_captures_lifetime_before_suspending(self):
        for name, end in [("completeTask", "undoTaskCompletion"), ("completeSelection", "undoSelectionCompletion")]:
            body = section(HOME, "private func " + name, "private func " + end)
            self.assertLess(body.index("let generation = visibilityGeneration"), body.index("await store."))
            self.assertLess(body.index("await store."), body.index("generation == visibilityGeneration"))
        self.assertIn("visibilityGeneration = UUID()", section(HOME, ".onAppear {", ".onDisappear"))
        self.assertIn("visibilityGeneration = UUID()", section(HOME, ".onDisappear {", ".onChange"))
        self.assertNotIn("visibilityGeneration", section(HOME, "private func cancelUndoTimer", "private func clearUndo"))

    def test_undo_context_progress_and_original_timeout_contract(self):
        for name, end in [("undoBar", "completeTask"), ("selectionUndoBar", "completeSelection")]:
            body = section(HOME, "private func " + name, "private func " + end)
            for token in ["store.company(id:", "ProgressView()", "戻しています", ".disabled(store.isSaving || isUndoing"]:
                self.assertIn(token, body)
        self.assertIn("!voiceOverEnabled", HOME)
        self.assertIn("Task.sleep(for: .seconds(6))", HOME)
        self.assertIn("$0.version == task.version", HOME)
        self.assertIn("$0.version == step.version", HOME)

    def test_calendar_day_change_only_refreshes_current_day(self):
        self.assertIn("publisher(for: .NSCalendarDayChanged)", CALENDAR)
        self.assertIn("if phase == .active { refreshCurrentDay() }", CALENDAR)
        refresh = section(CALENDAR, "private func refreshCurrentDay()", "private func moveToToday()")
        self.assertIn("currentDay =", refresh)
        self.assertNotIn("selectedDate =", refresh)
        self.assertNotIn("displayedMonth =", refresh)
        self.assertNotIn("isDateInToday", CALENDAR)
        self.assertIn("equalTo: currentDay, toGranularity: .month", CALENDAR)
        self.assertIn("isDate(date, inSameDayAs: currentDay)", CALENDAR)

    def test_calendar_announces_update_without_external_calendar(self):
        self.assertIn(".accessibilityLabel(event.isSaving(in: store)", CALENDAR)
        self.assertIn("を更新中", CALENDAR)
        self.assertNotIn("private func export(_ event: CalendarEvent)", CALENDAR)
        self.assertNotIn("private func removeExport(_ event: CalendarEvent)", CALENDAR)

    def test_existing_task_opens_detail_but_creation_keeps_editor(self):
        for source in [HOME, CALENDAR]:
            self.assertIn("TaskDetailView(taskID: task.id, ownerUserID: task.userID)", source)
            self.assertNotIn("TaskEditorView(task:", source)
            self.assertIn("ToDoの詳細を表示", source)
        self.assertIn("TaskEditorView()", HOME)
        self.assertIn("TaskEditorView(initialDueDate: selectedDate)", CALENDAR)


if __name__ == "__main__":
    unittest.main()
