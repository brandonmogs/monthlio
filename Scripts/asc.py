#!/usr/bin/env python3
"""App Store Connect API helper for Monthlio releases.

Authenticates with an App Store Connect API key (App Manager role) and
performs the release steps that otherwise need clicking:

  check         show the app, recent versions, builds and in-app purchases
  version       create the version if needed; set What's New, review notes,
                automatic release
  screenshots   upload a folder of PNGs to one display type of the en-US
                localization (skips files already present by name)
  iap           create the non-consumable if needed and complete its
                localization, price, availability and review screenshot;
                --submit sends it for review
  build         wait for the uploaded build to finish processing and attach
                it to the version
  submit        create the review submission for the version; --confirm
                actually submits (nothing is sent to review without it)
  cancel        withdraw the open review submission (developer removed
                from review); the version can be edited and resubmitted

Usage: asc.py --key-id K --issuer-id I --key-path AuthKey.p8 [--app ID] <command> [options]
Requires PyJWT and cryptography.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
DEFAULT_APP = "6810045540"


class ASC:
    def __init__(self, key_id, issuer_id, key_path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        with open(key_path) as f:
            self.private_key = f.read()
        self._token = None
        self._expires = 0

    def token(self):
        now = int(time.time())
        if self._token and now < self._expires - 60:
            return self._token
        payload = {"iss": self.issuer_id, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
        self._token = jwt.encode(payload, self.private_key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"})
        self._expires = now + 19 * 60
        return self._token

    def request(self, method, path=None, body=None, params=None, url=None):
        if url is None:
            url = API + path
            if params:
                url += "?" + urllib.parse.urlencode(params, doseq=True)
        headers = {"Authorization": "Bearer " + self.token()}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                text = response.read()
                return json.loads(text) if text else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise SystemExit(f"{method} {url} -> HTTP {error.code}\n{detail[:3000]}")

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)

    def get_optional(self, path):
        """A related resource that may not exist yet (Apple answers 404)."""
        url = API + path
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + self.token()})
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                text = response.read()
                return (json.loads(text) if text else {}).get("data")
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            detail = error.read().decode(errors="replace")
            raise SystemExit(f"GET {url} -> HTTP {error.code}\n{detail[:3000]}")

    def get_all(self, path, **params):
        items, url = [], None
        while True:
            page = self.request("GET", path, params=params or None) if url is None else self.request("GET", url=url)
            items += page.get("data", [])
            url = page.get("links", {}).get("next")
            if not url:
                return items

    def post(self, path, body):
        return self.request("POST", path, body=body)

    def patch(self, path, body):
        return self.request("PATCH", path, body=body)

    def delete(self, path):
        return self.request("DELETE", path)


def rel(type_name, identifier):
    return {"data": {"type": type_name, "id": identifier}}


def upload_asset(asc, type_name, create_path, relationships, file_path):
    """Reserve, upload in chunks, commit, and wait for the asset."""
    size = os.path.getsize(file_path)
    name = os.path.basename(file_path)
    created = asc.post(create_path, {"data": {"type": type_name, "attributes": {"fileName": name, "fileSize": size}, "relationships": relationships}})["data"]
    asset_id = created["id"]
    with open(file_path, "rb") as f:
        blob = f.read()
    for operation in created["attributes"]["uploadOperations"]:
        chunk = blob[operation["offset"]:operation["offset"] + operation["length"]]
        headers = {h["name"]: h["value"] for h in operation.get("requestHeaders", [])}
        req = urllib.request.Request(operation["url"], data=chunk, method=operation["method"], headers=headers)
        with urllib.request.urlopen(req, timeout=300) as response:
            response.read()
    checksum = hashlib.md5(blob).hexdigest()
    asc.patch(f"/v1/{type_name}/{asset_id}", {"data": {"type": type_name, "id": asset_id, "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}})
    for _ in range(60):
        state = asc.get(f"/v1/{type_name}/{asset_id}")["data"]["attributes"].get("assetDeliveryState", {}).get("state")
        if state == "COMPLETE":
            return asset_id
        if state == "FAILED":
            raise SystemExit(f"asset {name} failed processing")
        time.sleep(5)
    raise SystemExit(f"asset {name} still processing after 5 minutes")


# MARK: commands

def cmd_check(asc, app, args):
    info = asc.get(f"/v1/apps/{app}")["data"]["attributes"]
    print(f"App: {info['name']} ({info['bundleId']}), sku {info.get('sku')}")
    print("Versions:")
    for v in asc.get_all(f"/v1/apps/{app}/appStoreVersions", **{"limit": 10}):
        a = v["attributes"]
        print(f"  {a['versionString']:>6}  {a.get('appVersionState') or a.get('appStoreState')}  release={a.get('releaseType')}  id={v['id']}")
    print("Builds:")
    for b in asc.get_all("/v1/builds", **{"filter[app]": app, "sort": "-uploadedDate", "limit": 10, "include": "preReleaseVersion"}):
        a = b["attributes"]
        print(f"  build {a['version']:>3}  {a['processingState']:<10} uploaded {a.get('uploadedDate')}  expired={a.get('expired')}  id={b['id']}")
    print("In-app purchases:")
    for p in asc.get_all(f"/v1/apps/{app}/inAppPurchasesV2"):
        a = p["attributes"]
        print(f"  {a['productId']}  {a['inAppPurchaseType']}  state={a.get('state')}  id={p['id']}")
    print("Open review submissions:")
    for s in asc.get_all(f"/v1/apps/{app}/reviewSubmissions", **{"filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"}):
        print(f"  {s['attributes']['state']}  id={s['id']}")


def find_version(asc, app, version_string):
    for v in asc.get_all(f"/v1/apps/{app}/appStoreVersions", **{"filter[platform]": "IOS", "filter[versionString]": version_string}):
        return v
    return None


def localization(asc, version_id, locale="en-US"):
    for l in asc.get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"):
        if l["attributes"]["locale"] == locale:
            return l
    raise SystemExit(f"no {locale} localization on version {version_id}; add it in App Store Connect first")


def cmd_version(asc, app, args):
    version = find_version(asc, app, args.version)
    if version is None:
        version = asc.post("/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": args.version, "releaseType": "AFTER_APPROVAL"}, "relationships": {"app": rel("apps", app)}}})["data"]
        print(f"created version {args.version} ({version['id']})")
    else:
        print(f"version {args.version} exists ({version['id']}, {version['attributes'].get('appVersionState') or version['attributes'].get('appStoreState')})")
        if version["attributes"].get("releaseType") != "AFTER_APPROVAL":
            asc.patch(f"/v1/appStoreVersions/{version['id']}", {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": {"releaseType": "AFTER_APPROVAL"}}})
            print("  release type set to automatic")
    vid = version["id"]
    if args.whats_new:
        loc = localization(asc, vid)
        text = open(args.whats_new).read().strip()
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
        print(f"  What's New set ({len(text)} chars, en-US)")
    if args.review_note:
        notes = open(args.review_note).read().strip()
        detail = asc.get_optional(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        if detail:
            asc.patch(f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
        else:
            asc.post("/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": {"notes": notes}, "relationships": {"appStoreVersion": rel("appStoreVersions", vid)}}})
        print("  review notes set")


def cmd_screenshots(asc, app, args):
    version = find_version(asc, app, args.version) or sys.exit(f"version {args.version} not found")
    loc = localization(asc, version["id"])
    sets = asc.get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
    target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == args.display), None)
    if target is None:
        target = asc.post("/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": args.display}, "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", loc["id"])}}})["data"]
        print(f"created screenshot set {args.display}")
    existing = {s["attributes"]["fileName"] for s in asc.get_all(f"/v1/appScreenshotSets/{target['id']}/appScreenshots")}
    files = sorted(f for f in os.listdir(args.dir) if f.lower().endswith(".png"))
    for name in files:
        if name in existing:
            print(f"  {name}: already there")
            continue
        upload_asset(asc, "appScreenshots", "/v1/appScreenshots", {"appScreenshotSet": rel("appScreenshotSets", target["id"])}, os.path.join(args.dir, name))
        print(f"  {name}: uploaded")
    print("existing sets on this version:", ", ".join(s["attributes"]["screenshotDisplayType"] for s in sets) or "none")


def find_iap(asc, app, product_id):
    for p in asc.get_all(f"/v1/apps/{app}/inAppPurchasesV2", **{"filter[productId]": product_id}):
        return p
    return None


def cmd_iap(asc, app, args):
    iap = find_iap(asc, app, args.product_id)
    if iap is None:
        iap = asc.post("/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {"name": args.name, "productId": args.product_id, "inAppPurchaseType": "NON_CONSUMABLE", "reviewNote": args.review_note or "", "familySharable": True}, "relationships": {"app": rel("apps", app)}}})["data"]
        print(f"created in-app purchase {args.product_id} ({iap['id']})")
    else:
        print(f"in-app purchase {args.product_id} exists ({iap['id']}, state {iap['attributes'].get('state')})")
    iap_id = iap["id"]

    locs = asc.get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if en is None:
        asc.post("/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations", "attributes": {"locale": "en-US", "name": args.name, "description": args.description}, "relationships": {"inAppPurchaseV2": rel("inAppPurchases", iap_id)}}})
        print("  en-US localization created")
    elif en["attributes"].get("name") != args.name or en["attributes"].get("description") != args.description:
        asc.patch(f"/v1/inAppPurchaseLocalizations/{en['id']}", {"data": {"type": "inAppPurchaseLocalizations", "id": en["id"], "attributes": {"name": args.name, "description": args.description}}})
        print("  en-US localization updated")
    else:
        print("  en-US localization present")

    schedule = asc.get_optional(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
    if schedule is None:
        points = asc.get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints", **{"filter[territory]": "USA", "limit": 200})
        point = next((p for p in points if p["attributes"]["customerPrice"] == args.price), None)
        if point is None:
            raise SystemExit(f"no USA price point for {args.price}; available: " + ", ".join(sorted({p['attributes']['customerPrice'] for p in points}))[:500])
        asc.post("/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": rel("inAppPurchases", iap_id),
                "baseTerritory": rel("territories", "USA"),
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None}, "relationships": {"inAppPurchasePricePoint": rel("inAppPurchasePricePoints", point["id"])}}]})
        print(f"  price set to USD {args.price} (other territories follow Apple's equalization)")
    else:
        print("  price schedule present")

    availability = asc.get_optional(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if availability is None:
        territories = [t["id"] for t in asc.get_all("/v1/territories", limit=200)]
        asc.post("/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {"inAppPurchase": rel("inAppPurchases", iap_id), "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
        print(f"  available in {len(territories)} territories")
    else:
        print("  availability present")

    shot = asc.get_optional(f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    if shot is None and args.review_screenshot:
        upload_asset(asc, "inAppPurchaseAppStoreReviewScreenshots", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"inAppPurchaseV2": rel("inAppPurchases", iap_id)}, args.review_screenshot)
        print("  review screenshot uploaded")
    elif shot:
        print("  review screenshot present")

    if args.submit:
        asc.post("/v1/inAppPurchaseSubmissions", {"data": {"type": "inAppPurchaseSubmissions", "relationships": {"inAppPurchaseV2": rel("inAppPurchases", iap_id)}}})
        print("  submitted for review")
    state = asc.get(f"/v2/inAppPurchases/{iap_id}")["data"]["attributes"].get("state")
    print(f"  state: {state}")


def cmd_build(asc, app, args):
    version = find_version(asc, app, args.version) or sys.exit(f"version {args.version} not found")
    deadline = time.time() + args.wait * 60
    while True:
        builds = asc.get_all("/v1/builds", **{"filter[app]": app, "filter[version]": args.build, "include": "preReleaseVersion", "sort": "-uploadedDate"})
        match = next((b for b in builds if not b["attributes"].get("expired")), None)
        if match is None:
            status = "not yet visible"
        else:
            status = match["attributes"]["processingState"]
            if status == "VALID":
                break
            if status in ("FAILED", "INVALID"):
                raise SystemExit(f"build {args.build} is {status}")
        if time.time() > deadline:
            raise SystemExit(f"build {args.build}: {status} after {args.wait} minutes; run again later")
        print(f"  build {args.build}: {status}; checking again in 60s")
        time.sleep(60)
    asc.patch(f"/v1/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": match["id"]}})
    print(f"attached build {args.build} ({match['id']}) to version {args.version}")


def cmd_submit(asc, app, args):
    version = find_version(asc, app, args.version) or sys.exit(f"version {args.version} not found")
    open_subs = asc.get_all(f"/v1/apps/{app}/reviewSubmissions", **{"filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"})
    submission = next((s for s in open_subs if s["attributes"]["state"] in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")), None)
    if any(s["attributes"]["state"] in ("WAITING_FOR_REVIEW", "IN_REVIEW") for s in open_subs):
        raise SystemExit("a submission is already waiting for or in review")
    if submission and submission["attributes"]["state"] == "UNRESOLVED_ISSUES":
        print(f"reusing submission {submission['id']} that came back with unresolved issues")
    if submission is None:
        submission = asc.post("/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": rel("apps", app)}}})["data"]
        print(f"created review submission {submission['id']}")
    items = asc.get_all(f"/v1/reviewSubmissions/{submission['id']}/items", include="appStoreVersion")
    if not any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == version["id"] for i in items):
        asc.post("/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": rel("reviewSubmissions", submission["id"]), "appStoreVersion": rel("appStoreVersions", version["id"])}}})
        print(f"added version {args.version} to the submission")
    if args.iap_product_id:
        iap = find_iap(asc, app, args.iap_product_id)
        if iap and not any((i.get("relationships", {}).get("inAppPurchaseV2", {}).get("data") or {}).get("id") == iap["id"] for i in items):
            try:
                asc.post("/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": rel("reviewSubmissions", submission["id"]), "inAppPurchaseV2": rel("inAppPurchases", iap["id"])}}})
                print("added the in-app purchase to the submission")
            except SystemExit as error:
                print(f"in-app purchase not added as a submission item ({str(error).splitlines()[0]}); it is submitted separately")
    if args.confirm:
        asc.patch(f"/v1/reviewSubmissions/{submission['id']}", {"data": {"type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
        print("SUBMITTED for review")
    else:
        print("ready; run again with --confirm to submit for review")


def cmd_cancel(asc, app, args):
    open_subs = asc.get_all(f"/v1/apps/{app}/reviewSubmissions", **{"filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"})
    if not open_subs:
        print("no open review submission")
        return
    if args.submission_id:
        open_subs = [s for s in open_subs if s["id"] == args.submission_id] or sys.exit(f"no open submission {args.submission_id}")
    elif len(open_subs) > 1:
        raise SystemExit("several open submissions; pass --submission-id: " + ", ".join(f"{s['id']} ({s['attributes']['state']})" for s in open_subs))
    for submission in open_subs:
        asc.patch(f"/v1/reviewSubmissions/{submission['id']}", {"data": {"type": "reviewSubmissions", "id": submission["id"], "attributes": {"canceled": True}}})
        print(f"canceled review submission {submission['id']} (was {submission['attributes']['state']})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-id", default=os.environ.get("ASC_KEY_ID"), help="or ASC_KEY_ID")
    parser.add_argument("--issuer-id", default=os.environ.get("ASC_ISSUER_ID"), help="or ASC_ISSUER_ID")
    parser.add_argument("--key-path", default=os.environ.get("ASC_KEY_PATH"), help="or ASC_KEY_PATH")
    parser.add_argument("--app", default=DEFAULT_APP)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    p = sub.add_parser("version"); p.add_argument("--version", required=True); p.add_argument("--whats-new"); p.add_argument("--review-note")
    p = sub.add_parser("screenshots"); p.add_argument("--version", required=True); p.add_argument("--display", default="APP_IPAD_PRO_3GEN_129"); p.add_argument("--dir", required=True)
    p = sub.add_parser("iap"); p.add_argument("--product-id", required=True); p.add_argument("--name", required=True); p.add_argument("--description", required=True); p.add_argument("--price", default="9.99"); p.add_argument("--review-screenshot"); p.add_argument("--review-note"); p.add_argument("--submit", action="store_true")
    p = sub.add_parser("build"); p.add_argument("--version", required=True); p.add_argument("--build", required=True); p.add_argument("--wait", type=int, default=45, help="minutes to wait for processing")
    p = sub.add_parser("submit"); p.add_argument("--version", required=True); p.add_argument("--iap-product-id"); p.add_argument("--confirm", action="store_true")
    p = sub.add_parser("cancel"); p.add_argument("--submission-id")
    args = parser.parse_args()
    if not (args.key_id and args.issuer_id and args.key_path):
        parser.error("credentials required: --key-id/--issuer-id/--key-path or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH")
    asc = ASC(args.key_id, args.issuer_id, os.path.expanduser(args.key_path))
    {"check": cmd_check, "version": cmd_version, "screenshots": cmd_screenshots, "iap": cmd_iap, "build": cmd_build, "submit": cmd_submit, "cancel": cmd_cancel}[args.command](asc, args.app, args)


if __name__ == "__main__":
    main()
