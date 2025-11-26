--[[
    This is an alteration of the orignal 2-header-center.lua file 


    This user patch adds a "header" into the reader display, similar to the footer at the bottom.

    In THIS version, the header shows ONLY a centered clock at the top of the screen,
    Kindle-style. You can turn it on/off via Tools → Plugins → Patch Management.

    It is only drawn for "reflowable" documents like EPUB and not for "fixed layout"
    documents like PDF and CBZ.

    It is up to you to provide enough of a top margin so that your book contents are not
    obscured by the header. You'll know right away if you need to increase the top margin.

    The rest of the logic comes from the original centered-header patch; we just changed
    the part that decides what text is shown in the header.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local logger = require("logger")
local util = require("util")
local datetime = require("datetime")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderView = require("apps/reader/modules/readerview")
local _ReaderView_paintTo_orig = ReaderView.paintTo
local header_settings = G_reader_settings:readSetting("footer")
local screen_width = Screen:getWidth()

ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)
    -- Show only for epub-likes and never on pdf-likes
    if self.render_mode ~= nil then return end

    ------------------------------------------------------------------------
    -- CONFIG SECTION: tweak look of the clock header here if you want
    ------------------------------------------------------------------------
    local header_font_face = "ffont" -- same font the footer uses
    -- Example: use a specific serif font instead:
    -- header_font_face = "source/SourceSerif4-Regular.ttf"

    local header_font_size = header_settings.text_font_size or 14
    local header_font_bold = header_settings.text_font_bold or false
    local header_font_color = Blitbuffer.COLOR_BLACK -- you can try other shades
    local header_top_padding = Size.padding.small -- small / default / large
    local header_use_book_margins = true -- use same margins as book for header
    local header_margin = Size.padding.large -- used if header_use_book_margins = false
    local header_max_width_pct = 100 -- max width % before truncation (not critical for clock)

    ------------------------------------------------------------------------
    -- DATA GATHERING (title, page, etc.). Clock & battery are what we care about.
    ------------------------------------------------------------------------
    -- Title and Author(s) (kept for reference, but unused in the final header)
    local book_title = ""
    local book_author = ""
    if self.ui.doc_props then
        book_title = self.ui.doc_props.display_title or ""
        book_author = self.ui.doc_props.authors or ""
        if book_author:find("\n") then -- Show first author if multiple authors
            book_author =  T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
        end
    end

    -- Page count and percentage (kept, but unused in final header)
    local pageno = self.state.page or 1
    local pages = self.ui.doc_settings.data.doc_pages or 1
    local page_progress = ("%d / %d"):format(pageno, pages)
    local pages_left_book  = pages - pageno
    local percentage = (pageno / pages) * 100

    -- Chapter info (kept, but unused in final header)
    local book_chapter = ""
    local pages_chapter = 0
    local pages_left = 0
    local pages_done = 0
    if self.ui.toc then
        book_chapter = self.ui.toc:getTocTitleByPage(pageno) or ""
        pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
        pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
        pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
    end
    pages_done = pages_done + 1
    local chapter_progress = pages_done .. " ⁄⁄ " .. pages_chapter

    -- Clock: respects 12h / 24h reader setting
    local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) or ""

    -- Battery (optional, we can prepend/append it if you want)
    local battery = ""
    if Device:hasBattery() then
        local power_dev = Device:getPowerDevice()
        local batt_lvl = power_dev:getCapacity() or 0
        local is_charging = power_dev:isCharging() or false
        local batt_prefix = power_dev:getBatterySymbol(power_dev:isCharged(), is_charging, batt_lvl) or ""
        battery = batt_prefix .. batt_lvl .. "%"
    end

    ------------------------------------------------------------------------
    -- WHAT IS ACTUALLY SHOWN IN THE HEADER (THIS IS THE IMPORTANT BIT)
    ------------------------------------------------------------------------

    -- PURE CLOCK VERSION:
    -- Only show the time in the center, Kindle-style.
    local centered_header = time

    -- If you want time + battery instead, you could use:
    -- local centered_header = string.format("%s   %s", battery, time)

    ------------------------------------------------------------------------
    -- LAYOUT & DRAWING (you generally don't need to change this)
    ------------------------------------------------------------------------
    local margins = 0
    local left_margin = header_margin
    local right_margin = header_margin
    if header_use_book_margins then
        local page_margins = self.document:getPageMargins() or {}
        left_margin = page_margins.left or header_margin
        right_margin = page_margins.right or header_margin
    end
    margins = left_margin + right_margin
    local avail_width = screen_width - margins

    local function getFittedText(text, max_width_pct)
        if text == nil or text == "" then
            return ""
        end
        local text_widget = TextWidget:new{
            text = text:gsub(" ", "\u{00A0}"), -- no-break-space
            max_width = avail_width * max_width_pct * (1/100),
            face = Font:getFace(header_font_face, header_font_size),
            bold = header_font_bold,
            padding = 0,
        }
        local fitted_text, add_ellipsis = text_widget:getFittedText()
        text_widget:free()
        if add_ellipsis then
            fitted_text = fitted_text .. "…"
        end
        return BD.auto(fitted_text)
    end

    centered_header = getFittedText(centered_header, header_max_width_pct)

    local header_text = TextWidget:new{
        text = centered_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }

    local header = CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = header_text:getSize().h + header_top_padding },
        VerticalGroup:new{
            VerticalSpan:new{ width = header_top_padding },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_margin },
                header_text,
                HorizontalSpan:new{ width = right_margin },
            },
        },
    }

    header:paintTo(bb, x, y)
end
