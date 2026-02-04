#!/usr/bin/env python3

"""
Cedar Shiny Browser Test Script
================================
Automates browser testing of Shiny application functionality.

Requirements:
    pip install selenium

Usage:
    python3 test-shiny-browser.py [options]

Options:
    --headless      Run browser in headless mode (no GUI)
    --timeout N     Timeout in seconds (default: 30)
    --test NAME     Run specific test (default: all)

Available Tests:
    - dept_filter           Test department filter (select HIST, term 202580, refresh)
    - low_enrollment_alert  Test low enrollment alert (select HIST, term 202610, generate dashboard)
    - enrollment            Test enrollment tab functionality
    - headcount             Test headcount tab (select college, dept, generate table)
    - seatfinder            Test seatfinder tab (select college AS, term 202610, level lower)
    - all                   Run all tests (default)

Example:
    python3 test-shiny-browser.py --headless --test dept_filter
"""

import sys
import time
import argparse
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException

# ANSI colors
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

APP_URL = "http://localhost:3838/cedar/"

class ShinyTester:
    def __init__(self, headless=False, timeout=30):
        self.timeout = timeout
        self.driver = None
        self.headless = headless
        self.errors = []
        self.passed = []

    def setup(self):
        """Initialize Chrome driver"""
        print(f"{BLUE}Setting up browser...{NC}")
        chrome_options = Options()
        if self.headless:
            chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--window-size=1920,1080")

        try:
            self.driver = webdriver.Chrome(options=chrome_options)
            self.driver.set_page_load_timeout(self.timeout)
            print(f"{GREEN}✓ Browser ready{NC}")
            return True
        except Exception as e:
            print(f"{RED}✗ Failed to initialize browser: {e}{NC}")
            print(f"{YELLOW}Hint: Install ChromeDriver with: brew install chromedriver{NC}")
            return False

    def teardown(self):
        """Close browser"""
        if self.driver:
            self.driver.quit()
            print(f"{BLUE}Browser closed{NC}")

    def load_app(self):
        """Load the Shiny app"""
        print(f"\n{BLUE}[Test] Loading app: {APP_URL}{NC}")
        try:
            self.driver.get(APP_URL)

            # Wait for Shiny to be ready (look for known element)
            WebDriverWait(self.driver, self.timeout).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )

            # Wait a bit for Shiny to initialize
            time.sleep(2)

            print(f"{GREEN}✓ App loaded successfully{NC}")
            self.passed.append("App Loading")
            return True

        except TimeoutException:
            print(f"{RED}✗ Timeout loading app{NC}")
            self.errors.append("App failed to load within timeout")
            return False
        except Exception as e:
            print(f"{RED}✗ Error loading app: {e}{NC}")
            self.errors.append(f"App loading error: {e}")
            return False

    def test_dept_filter(self):
        """Test department filter: Select HIST, term 202580, click refresh"""
        print(f"\n{BLUE}[Test] Department Filter (HIST, 202580, refresh){NC}")

        try:
            # Wait for selectize inputs to be ready (they're async)
            time.sleep(3)

            # Check for and dismiss any modals that might be blocking
            try:
                modal = self.driver.find_element(By.CSS_SELECTOR, ".modal.show")
                print("  Detected modal dialog, attempting to dismiss...")
                # Try to find and click close button
                close_buttons = self.driver.find_elements(By.CSS_SELECTOR, ".modal button[data-dismiss='modal'], .modal .close")
                if close_buttons:
                    close_buttons[0].click()
                    time.sleep(1)
                    print(f"{GREEN}  ✓ Modal dismissed{NC}")
            except NoSuchElementException:
                pass  # No modal present, continue

            # Wait for any blocking modals to disappear
            WebDriverWait(self.driver, 10).until(
                EC.invisibility_of_element_located((By.CSS_SELECTOR, ".modal.show"))
            )

            # Find and select department dropdown (selectizeInput)
            print("  Selecting department: HIST...")

            # Wait for the element to be clickable, not just present
            dept_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#enrl_dept + .selectize-control input"))
            )

            # Type into selectize input
            dept_input.click()
            dept_input.send_keys("HIST")
            time.sleep(1)

            # Click the dropdown option
            dept_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='HIST']"))
            )
            dept_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Department selected{NC}")

            # Find and select term dropdown (also selectizeInput)
            print("  Selecting term: 202580...")

            term_input = WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, "#enrl_term + .selectize-control input"))
            )

            term_input.click()
            term_input.send_keys("202580")
            time.sleep(1)

            # Click the dropdown option
            term_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='202580']"))
            )
            term_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Term selected{NC}")

            # Find and click refresh button
            print("  Clicking refresh button...")
            refresh_btn = self.driver.find_element(By.ID, "enrl_button")
            refresh_btn.click()

            # Wait for table to update (look for table element)
            time.sleep(3)

            print(f"{GREEN}  ✓ Refresh button clicked{NC}")

            # Check if table is present
            try:
                table = self.driver.find_element(By.CSS_SELECTOR, ".dataTables_wrapper")
                print(f"{GREEN}  ✓ Table rendered{NC}")
            except NoSuchElementException:
                print(f"{YELLOW}  ⚠ Table not found (may still be loading){NC}")

            # Check for Shiny errors in page
            if "An error has occurred" in self.driver.page_source:
                print(f"{RED}✗ Shiny error detected in page{NC}")
                self.errors.append("Shiny error after department filter")
                return False

            print(f"{GREEN}✓ Department filter test passed{NC}")
            self.passed.append("Department Filter")
            return True

        except TimeoutException:
            print(f"{RED}✗ Timeout waiting for elements{NC}")
            self.errors.append("Department filter timeout")
            return False
        except Exception as e:
            print(f"{RED}✗ Error in department filter test: {e}{NC}")
            self.errors.append(f"Department filter error: {e}")
            return False

    def test_low_enrollment_alert(self):
        """Test low enrollment alert: Select HIST, term 202610, generate dashboard"""
        print(f"\n{BLUE}[Test] Low Enrollment Alert (HIST, 202610, generate dashboard){NC}")

        try:
            # Wait for selectize inputs to be ready
            time.sleep(3)

            # Check for and dismiss any modals that might be blocking
            try:
                modal = self.driver.find_element(By.CSS_SELECTOR, ".modal.show")
                print("  Detected modal dialog, attempting to dismiss...")
                close_buttons = self.driver.find_elements(By.CSS_SELECTOR, ".modal button[data-dismiss='modal'], .modal .close")
                if close_buttons:
                    close_buttons[0].click()
                    time.sleep(1)
                    print(f"{GREEN}  ✓ Modal dismissed{NC}")
            except NoSuchElementException:
                pass

            # Wait for any blocking modals to disappear
            WebDriverWait(self.driver, 10).until(
                EC.invisibility_of_element_located((By.CSS_SELECTOR, ".modal.show"))
            )

            # Click Low Enrollment Alert tab first
            print("  Clicking Low Enrollment Alert tab...")
            alert_tab = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.LINK_TEXT, "Low Enrollment Alert"))
            )
            alert_tab.click()
            time.sleep(2)

            print(f"{GREEN}  ✓ Low Enrollment Alert tab activated{NC}")

            # Find and select department dropdown
            print("  Selecting department: HIST...")

            dept_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#enrl_dept + .selectize-control input"))
            )

            dept_input.click()
            dept_input.send_keys("HIST")
            time.sleep(1)

            # Click the dropdown option
            dept_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='HIST']"))
            )
            dept_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Department selected{NC}")

            # Find and select term dropdown
            print("  Selecting term: 202610...")

            term_input = WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, "#enrl_term + .selectize-control input"))
            )

            term_input.click()
            term_input.send_keys("202610")
            time.sleep(1)

            # Click the dropdown option
            term_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='202610']"))
            )
            term_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Term selected{NC}")

            # Find and click Generate Alert Dashboard button
            print("  Clicking Generate Alert Dashboard button...")
            generate_btn = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Generate Alert Dashboard')]"))
            )
            generate_btn.click()
            time.sleep(3)

            print(f"{GREEN}  ✓ Generate Alert Dashboard button clicked{NC}")

            # Check for Shiny errors
            if "An error has occurred" in self.driver.page_source:
                print(f"{RED}✗ Shiny error detected in page{NC}")
                self.errors.append("Shiny error after low enrollment alert generation")
                return False

            print(f"{GREEN}✓ Low enrollment alert test passed{NC}")
            self.passed.append("Low Enrollment Alert")
            return True

        except TimeoutException:
            print(f"{RED}✗ Timeout waiting for elements{NC}")
            self.errors.append("Low enrollment alert timeout")
            return False
        except Exception as e:
            print(f"{RED}✗ Error in low enrollment alert test: {e}{NC}")
            self.errors.append(f"Low enrollment alert error: {e}")
            return False

    def test_enrollment_tab(self):
        """Test enrollment tab functionality"""
        print(f"\n{BLUE}[Test] Enrollment Tab{NC}")

        try:
            # Click enrollment tab
            print("  Clicking Enrollment tab...")
            enrollment_tab = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.LINK_TEXT, "Enrollment"))
            )
            enrollment_tab.click()
            time.sleep(2)

            print(f"{GREEN}  ✓ Enrollment tab activated{NC}")

            # Check if enrollment controls are present
            try:
                self.driver.find_element(By.ID, "enrl_dept")
                print(f"{GREEN}  ✓ Enrollment controls present{NC}")
            except NoSuchElementException:
                print(f"{RED}  ✗ Enrollment controls not found{NC}")
                self.errors.append("Enrollment controls missing")
                return False

            print(f"{GREEN}✓ Enrollment tab test passed{NC}")
            self.passed.append("Enrollment Tab")
            return True

        except Exception as e:
            print(f"{RED}✗ Error in enrollment tab test: {e}{NC}")
            self.errors.append(f"Enrollment tab error: {e}")
            return False

    def test_headcount_tab(self):
        """Test headcount tab functionality: select college, dept, generate table"""
        print(f"\n{BLUE}[Test] Headcount Tab (College → Dept → Generate){NC}")

        try:
            # Wait for selectize inputs to be ready
            time.sleep(3)

            # Check for and dismiss any modals that might be blocking
            try:
                modal = self.driver.find_element(By.CSS_SELECTOR, ".modal.show")
                print("  Detected modal dialog, attempting to dismiss...")
                close_buttons = self.driver.find_elements(By.CSS_SELECTOR, ".modal button[data-dismiss='modal'], .modal .close")
                if close_buttons:
                    close_buttons[0].click()
                    time.sleep(1)
                    print(f"{GREEN}  ✓ Modal dismissed{NC}")
            except NoSuchElementException:
                pass  # No modal present, continue

            # Click headcount tab
            print("  Clicking Headcount tab...")
            headcount_tab = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.LINK_TEXT, "Headcount"))
            )
            headcount_tab.click()
            time.sleep(2)

            print(f"{GREEN}  ✓ Headcount tab activated{NC}")

            # Wait for any blocking modals to disappear
            WebDriverWait(self.driver, 10).until(
                EC.invisibility_of_element_located((By.CSS_SELECTOR, ".modal.show"))
            )

            # Select college dropdown
            print("  Selecting college: College of Arts and Sciences...")

            college_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#hc_college + .selectize-control input"))
            )

            college_input.click()
            college_input.send_keys("Arts")  # Partial match for "College of Arts and Sciences"
            time.sleep(1)

            # Click the dropdown option (look for partial match)
            college_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[contains(@data-value, 'Arts')]"))
            )
            college_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ College selected{NC}")

            # Select department dropdown
            print("  Selecting department: HIST...")

            dept_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#hc_dept + .selectize-control input"))
            )

            dept_input.click()
            dept_input.send_keys("HIST")
            time.sleep(1)

            # Click the dropdown option
            dept_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='HIST']"))
            )
            dept_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Department selected{NC}")

            # Click the "Update Table" or "Generate" button
            print("  Clicking Generate button...")
            generate_btn = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.ID, "hc_button"))
            )
            generate_btn.click()

            # Wait for results to load
            time.sleep(3)

            print(f"{GREEN}  ✓ Generate button clicked{NC}")

            # Check if table/results are present
            try:
                # Look for headcount-specific outputs (plotly charts or datatable)
                result_element = self.driver.find_element(By.CSS_SELECTOR, "#hc_undergrad_plot, #hc_grad_plot, .dataTables_wrapper")
                print(f"{GREEN}  ✓ Results rendered (plot or table found){NC}")
            except NoSuchElementException:
                print(f"{YELLOW}  ⚠ Results element not found (may still be loading){NC}")

            # Check for Shiny errors in page
            if "An error has occurred" in self.driver.page_source:
                print(f"{RED}✗ Shiny error detected in page{NC}")
                self.errors.append("Shiny error after headcount generation")
                return False

            print(f"{GREEN}✓ Headcount tab test passed{NC}")
            self.passed.append("Headcount Tab")
            return True

        except TimeoutException:
            print(f"{RED}✗ Timeout waiting for headcount elements{NC}")
            self.errors.append("Headcount tab timeout")
            return False
        except Exception as e:
            print(f"{RED}✗ Error in headcount tab test: {e}{NC}")
            self.errors.append(f"Headcount tab error: {e}")
            return False

    def test_seatfinder_tab(self):
        """Test seatfinder tab functionality: select college AS, term 202610, level lower"""
        print(f"\n{BLUE}[Test] Seatfinder Tab (College AS, Term 202610, Level lower){NC}")

        try:
            # Wait for page to be ready
            time.sleep(3)

            # Check for and dismiss any modals that might be blocking
            try:
                modal = self.driver.find_element(By.CSS_SELECTOR, ".modal.show")
                print("  Detected modal dialog, attempting to dismiss...")
                close_buttons = self.driver.find_elements(By.CSS_SELECTOR, ".modal button[data-dismiss='modal'], .modal .close")
                if close_buttons:
                    close_buttons[0].click()
                    time.sleep(1)
                    print(f"{GREEN}  ✓ Modal dismissed{NC}")
            except NoSuchElementException:
                pass  # No modal present, continue

            # Click Seatfinder tab
            print("  Clicking Seatfinder tab...")
            seatfinder_tab = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.LINK_TEXT, "Seatfinder"))
            )
            seatfinder_tab.click()
            time.sleep(2)

            print(f"{GREEN}  ✓ Seatfinder tab activated{NC}")

            # Wait for any blocking modals to disappear
            WebDriverWait(self.driver, 10).until(
                EC.invisibility_of_element_located((By.CSS_SELECTOR, ".modal.show"))
            )

            # Select college dropdown (AS)
            print("  Selecting college: AS...")

            college_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#sf_college + .selectize-control input"))
            )

            college_input.click()
            college_input.send_keys("AS")
            time.sleep(1)

            # Click the dropdown option
            college_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='AS']"))
            )
            college_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ College selected{NC}")

            # Select term dropdown (202610)
            print("  Selecting term: 202610...")

            term_input = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.CSS_SELECTOR, "#sf_term + .selectize-control input"))
            )

            term_input.click()
            term_input.send_keys("202610")
            time.sleep(1)

            # Click the dropdown option
            term_option = WebDriverWait(self.driver, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//div[@data-value='202610']"))
            )
            term_option.click()
            time.sleep(1)

            print(f"{GREEN}  ✓ Term selected{NC}")

            # Select level dropdown (lower) - this is a regular selectInput, not selectize
            print("  Selecting level: lower...")

            # For regular selectInput, use Select class
            level_select = WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located((By.ID, "sf_level"))
            )
            Select(level_select).select_by_value("lower")
            time.sleep(1)

            print(f"{GREEN}  ✓ Level selected{NC}")

            # Click the Refresh table button
            print("  Clicking Refresh table button...")
            refresh_btn = WebDriverWait(self.driver, 10).until(
                EC.element_to_be_clickable((By.ID, "sf_button"))
            )
            refresh_btn.click()

            # Wait for results to load (seatfinder can take a while)
            print("  Waiting for seatfinder to process (this may take a few seconds)...")
            time.sleep(8)

            print(f"{GREEN}  ✓ Refresh button clicked{NC}")

            # Check for specific error messages
            page_source = self.driver.page_source

            # Check for the specific hr_data error
            if "object 'hr_data' not found" in page_source:
                print(f"{RED}✗ Found error: object 'hr_data' not found{NC}")
                self.errors.append("Seatfinder error: object 'hr_data' not found")
                return False

            # Check for general Shiny errors
            if "An error has occurred" in page_source:
                # Try to extract the error message
                try:
                    error_elem = self.driver.find_element(By.CSS_SELECTOR, ".shiny-output-error-validation, .shiny-output-error")
                    error_text = error_elem.text
                    print(f"{RED}✗ Shiny error detected: {error_text}{NC}")
                    self.errors.append(f"Seatfinder Shiny error: {error_text}")
                except NoSuchElementException:
                    print(f"{RED}✗ Shiny error detected in page{NC}")
                    self.errors.append("Seatfinder Shiny error detected")
                return False

            # Check if results table is present
            try:
                result_element = self.driver.find_element(By.CSS_SELECTOR, "#type_summary .dataTables_wrapper, #type_summary table")
                print(f"{GREEN}  ✓ Results table rendered{NC}")
            except NoSuchElementException:
                print(f"{YELLOW}  ⚠ Results table not found (may still be loading or empty){NC}")

            print(f"{GREEN}✓ Seatfinder tab test passed{NC}")
            self.passed.append("Seatfinder Tab")
            return True

        except TimeoutException:
            print(f"{RED}✗ Timeout waiting for seatfinder elements{NC}")
            self.errors.append("Seatfinder tab timeout")
            return False
        except Exception as e:
            print(f"{RED}✗ Error in seatfinder tab test: {e}{NC}")
            self.errors.append(f"Seatfinder tab error: {e}")
            return False

    def check_for_shiny_errors(self):
        """Check page for Shiny error messages"""
        print(f"\n{BLUE}[Test] Checking for Shiny errors...{NC}")

        error_indicators = [
            "An error has occurred",
            "Error:",
            "object '.+' not found",
            "could not find function",
            "unexpected symbol"
        ]

        page_source = self.driver.page_source
        found_errors = []

        for indicator in error_indicators:
            if indicator in page_source:
                found_errors.append(indicator)

        if found_errors:
            print(f"{RED}✗ Found error indicators: {', '.join(found_errors)}{NC}")
            self.errors.append("Shiny errors in page source")
            return False
        else:
            print(f"{GREEN}✓ No Shiny errors detected{NC}")
            return True

    def run_tests(self, test_name="all"):
        """Run specified test(s)"""
        print(f"\n{BLUE}{'='*70}{NC}")
        print(f"{BLUE}Cedar Shiny Browser Tests{NC}")
        print(f"{BLUE}{'='*70}{NC}")

        if not self.setup():
            return False

        try:
            # Always load app first
            if not self.load_app():
                return False

            # Run specified test(s)
            if test_name == "all":
                self.test_enrollment_tab()
                self.test_dept_filter()
                self.test_low_enrollment_alert()
                self.test_headcount_tab()
                self.test_seatfinder_tab()
                self.check_for_shiny_errors()
            elif test_name == "dept_filter":
                self.test_dept_filter()
            elif test_name == "low_enrollment_alert":
                self.test_low_enrollment_alert()
            elif test_name == "enrollment":
                self.test_enrollment_tab()
            elif test_name == "headcount":
                self.test_headcount_tab()
            elif test_name == "seatfinder":
                self.test_seatfinder_tab()
            else:
                print(f"{RED}Unknown test: {test_name}{NC}")
                return False

            # Summary
            print(f"\n{BLUE}{'='*70}{NC}")
            print(f"{BLUE}Test Summary{NC}")
            print(f"{BLUE}{'='*70}{NC}")
            print(f"Passed: {len(self.passed)}")
            for test in self.passed:
                print(f"  {GREEN}✓ {test}{NC}")

            if self.errors:
                print(f"\nFailed: {len(self.errors)}")
                for error in self.errors:
                    print(f"  {RED}✗ {error}{NC}")
                print(f"\n{RED}❌ Some tests failed{NC}")
                return False
            else:
                print(f"\n{GREEN}✅ All tests passed!{NC}")
                return True

        finally:
            self.teardown()


def main():
    parser = argparse.ArgumentParser(
        description="Browser automation tests for Cedar Shiny app"
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run browser in headless mode"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Timeout in seconds (default: 30)"
    )
    parser.add_argument(
        "--test",
        type=str,
        default="all",
        choices=["all", "dept_filter", "low_enrollment_alert", "enrollment", "headcount", "seatfinder"],
        help="Test to run (default: all)"
    )

    args = parser.parse_args()

    tester = ShinyTester(headless=args.headless, timeout=args.timeout)
    success = tester.run_tests(test_name=args.test)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
