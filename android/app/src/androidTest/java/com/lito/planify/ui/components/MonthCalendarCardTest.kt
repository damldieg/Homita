package com.lito.planify.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.lito.planify.ui.theme.PlanifyTheme
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class MonthCalendarCardTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var sections: PagerState
    private val currentMonth = YearMonth.now()

    private fun showCalendar(section: Int, onDayClick: (LocalDate) -> Unit = {}) {
        compose.setContent {
            PlanifyTheme {
                sections = rememberPagerState(initialPage = section, pageCount = { 3 })
                HorizontalPager(state = sections, modifier = Modifier.fillMaxSize()) { page ->
                    LazyColumn(Modifier.fillMaxSize()) {
                        item {
                            MonthCalendarCard(
                                eventColorsByDate = mapOf(currentMonth.plusMonths(1).atDay(15) to listOf(Color.Red)),
                                modifier = Modifier.testTag("month-$page"),
                                onDayClick = onDayClick
                            )
                        }
                        item {
                            Box(Modifier.fillMaxWidth().height(120.dp).testTag("section-$page"))
                        }
                    }
                }
            }
        }
    }

    private fun assertMonth(month: YearMonth) {
        val locale = InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration.locales[0]
        val name = month.month.getDisplayName(TextStyle.FULL_STANDALONE, locale).replaceFirstChar { it.uppercaseChar() }
        val title = if (month.year == currentMonth.year) name else "$name ${month.year}"
        compose.onNodeWithText(title).assertIsDisplayed()
    }

    @Test fun eventsCalendarSwipeChangesMonthAndKeepsDayClick() {
        var clickedDate: LocalDate? = null
        showCalendar(section = 0, onDayClick = { clickedDate = it })

        compose.onNodeWithTag("month-0").performTouchInput { swipeLeft() }

        compose.runOnIdle { assertEquals(0, sections.currentPage) }
        assertMonth(currentMonth.plusMonths(1))
        compose.onNode(hasText("15") and hasClickAction()).performClick()
        compose.runOnIdle { assertEquals(currentMonth.plusMonths(1).atDay(15), clickedDate) }
    }

    @Test fun routinesCalendarSwipesBothWaysWithoutChangingSection() {
        showCalendar(section = 1)

        compose.onNodeWithTag("month-1").performTouchInput { swipeRight() }
        compose.runOnIdle { assertEquals(1, sections.currentPage) }
        assertMonth(currentMonth.minusMonths(1))

        compose.onNodeWithTag("month-1").performTouchInput { swipeLeft() }
        assertMonth(currentMonth)
        compose.onNodeWithTag("month-1").performTouchInput { swipeLeft() }
        compose.runOnIdle { assertEquals(1, sections.currentPage) }
        assertMonth(currentMonth.plusMonths(1))
    }

    @Test fun swipeOutsideCalendarStillChangesSection() {
        showCalendar(section = 0)

        compose.onNodeWithTag("section-0").performTouchInput { swipeLeft() }

        compose.runOnIdle { assertEquals(1, sections.currentPage) }
    }

    @Test fun swipingAcrossDecemberShowsJanuaryWithItsYear() {
        showCalendar(section = 0)
        val monthsUntilJanuary = 13 - currentMonth.monthValue

        repeat(monthsUntilJanuary) {
            compose.onNodeWithTag("month-0").performTouchInput { swipeLeft() }
        }

        compose.runOnIdle { assertEquals(0, sections.currentPage) }
        assertMonth(currentMonth.plusMonths(monthsUntilJanuary.toLong()))
    }
}
