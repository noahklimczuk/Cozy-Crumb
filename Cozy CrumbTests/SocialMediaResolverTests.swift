//
//  SocialMediaResolverTests.swift
//  Cozy CrumbTests
//
//  The parsing half of the social media lookup — the half that can be tested
//  without a network, and the half that breaks when a platform reshuffles its
//  markup.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Instagram post URLs")
struct InstagramShortcodeTests {

    @Test("Posts, reels and IGTV all yield their shortcode")
    func shortcodes() throws {
        let cases = [
            "https://www.instagram.com/p/C8xYz1AbCdE/": "C8xYz1AbCdE",
            "https://www.instagram.com/reel/C8xYz1AbCdE/": "C8xYz1AbCdE",
            "https://www.instagram.com/reels/C8xYz1AbCdE/": "C8xYz1AbCdE",
            "https://instagram.com/tv/C8xYz1AbCdE": "C8xYz1AbCdE",
            "https://www.instagram.com/somecook/reel/C8xYz1AbCdE/": "C8xYz1AbCdE"
        ]

        for (link, expected) in cases {
            let url = try #require(URL(string: link))
            #expect(SocialMediaResolver.instagramShortcode(from: url) == expected)
        }
    }

    @Test("A profile link has no post to read")
    func profileLink() throws {
        let url = try #require(URL(string: "https://www.instagram.com/somecook/"))
        #expect(SocialMediaResolver.instagramShortcode(from: url) == nil)
    }

    @Test("The embed URL is the public, logged-out one")
    func embedURL() throws {
        let embed = try #require(SocialMediaResolver.instagramEmbedURL(shortcode: "C8xYz1AbCdE"))
        #expect(embed.absoluteString == "https://www.instagram.com/p/C8xYz1AbCdE/embed/captioned/")
    }

    @Test("The caption comes out of the embed page's markup")
    func embedCaption() {
        let html = """
        <div class="Caption"><a class="Username">somecook</a> \
        Weeknight gochujang noodles — the whole thing is in the video, I promise 🍜
        <span class="CaptionComments">View all 40 comments</span></div>
        """

        let caption = SocialMediaResolver.instagramEmbedCaption(inHTML: html)
        #expect(caption?.contains("gochujang noodles") == true)
    }
}

@Suite("Post media scraping")
struct SocialMediaScrapingTests {

    @Test("Open Graph video and image are picked up")
    func openGraphMedia() throws {
        let html = """
        <meta property="og:video" content="https://cdn.example.com/reel.mp4">
        <meta property="og:image" content="https://cdn.example.com/cover.jpg">
        <meta property="og:description" content="the best 20 minute pasta you will ever make, recipe in the video">
        """

        let media = SocialMediaResolver.media(inHTML: html, sourceURL: URL(string: "https://www.instagram.com/reel/abc/"))

        #expect(media.videoURL?.absoluteString == "https://cdn.example.com/reel.mp4")
        #expect(media.imageURLs.first?.absoluteString == "https://cdn.example.com/cover.jpg")
        #expect(media.caption?.hasPrefix("the best 20 minute") == true)
    }

    @Test("TikTok's escaped play address is unpicked")
    func tikTokPlayAddress() {
        let html = #"{"desc":"crispy chilli beef, full method in the vid","playAddr":"https:\/\/v16.tiktok.com\/video\/tos.mp4?a=1988&br=2","other":"x"}"#

        let media = SocialMediaResolver.media(inHTML: html, sourceURL: nil)

        #expect(media.videoURL?.absoluteString == "https://v16.tiktok.com/video/tos.mp4?a=1988&br=2")
        #expect(media.caption == "crispy chilli beef, full method in the vid")
    }

    @Test("Carousel slides are collected, in order and without duplicates")
    func carouselImages() {
        let html = #"""
        <meta property="og:image" content="https://cdn.example.com/cover.jpg">
        {"display_url":"https:\/\/cdn.example.com\/cover.jpg"}
        {"display_url":"https:\/\/cdn.example.com\/slide2.jpg"}
        {"display_url":"https:\/\/cdn.example.com\/slide3.jpg"}
        """#

        let media = SocialMediaResolver.media(inHTML: html, sourceURL: nil)

        #expect(media.imageURLs.map(\.absoluteString) == [
            "https://cdn.example.com/cover.jpg",
            "https://cdn.example.com/slide2.jpg",
            "https://cdn.example.com/slide3.jpg"
        ])
    }

    @Test("A page with nothing on it comes back empty rather than failing")
    func emptyPage() {
        let media = SocialMediaResolver.media(inHTML: "<html><body>Log in to continue</body></html>", sourceURL: nil)
        #expect(media.isEmpty)
    }

    @Test("The longest caption on offer wins")
    func longestCaption() {
        let html = #"""
        <meta property="og:description" content="short one">
        {"desc":"a much longer caption that actually says something about the dish"}
        """#

        let media = SocialMediaResolver.media(inHTML: html, sourceURL: nil)
        #expect(media.caption?.hasPrefix("a much longer") == true)
    }

    @Test("JSON escapes are unpicked, including unicode ones")
    func unescaping() {
        #expect(SocialMediaResolver.unescapedJSONString(#"https:\/\/example.com\/a?b=1&c=2"#)
            == "https://example.com/a?b=1&c=2")
        #expect(SocialMediaResolver.unescapedJSONString("plain") == "plain")
        #expect(SocialMediaResolver.unescapedJSONString(#"café"#) == "café")
    }
}
