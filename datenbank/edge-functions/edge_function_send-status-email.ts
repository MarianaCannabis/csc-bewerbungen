// ============================================================================
// Supabase Edge Function: send-status-email
// 
// Sendet automatisch eine E-Mail an den Bewerber bei Status-Wechsel.
// Wird durch DB-Webhook getriggert wenn sich csc_bewerbungen.status aendert.
// 
// Erwartetes Payload (von DB-Webhook):
// {
//   "type": "UPDATE",
//   "table": "csc_bewerbungen",
//   "record": { ... aktuelle Zeile ... },
//   "old_record": { ... vorherige Zeile ... },
//   "schema": "public"
// }
// 
// Status-Templates:
// - eingegangen: keine Mail (kommt schon bei Einreichung)
// - in_pruefung: kurze Info "wir schauen uns deine Bewerbung an"
// - eingeladen:  Einladungs-Mail mit Hinweis dass Vorstand sich meldet
// - warteliste:  freundliche Warteliste-Info
// - angenommen:  Glueckwunsch + Naechste-Schritte
// - abgelehnt:   freundliche Absage
// ============================================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import nodemailer from 'npm:nodemailer@6.9.13';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// Rollen- und Vertrags-Labels (synchron zum Dashboard)
// ============================================================================
const ROLE_LABELS: Record<string, string> = {
  vorstand: 'Vorstand', stellv_vorstand: 'Stellv. Vorstand',
  grower: 'Grower', head_grower: 'Head Grower', ausgabe: 'Ausgabe',
  springer: 'Springer', praevention: 'Präventionsbeauftragte:r',
  sicherheit: 'Sicherheit', reinigung: 'Reinigung',
};
const VERTRAG_LABELS: Record<string, string> = {
  minijob: 'Minijob', teilzeit: 'Teilzeit', vollzeit: 'Vollzeit', ehrenamt: 'Ehrenamt',
};

// Basis-URL der Bewerber-Status-Seite (fuer den Vertragsdaten-Link in der
// Annahme-Mail). Bei Bedarf per Environment-Variable ueberschreibbar.
const STATUS_BASE_URL = Deno.env.get('STATUS_BASE_URL')
  || 'https://marianacannabis.github.io/csc-bewerbungen/status/';

// Formatiert eingestellt_details → lesbarer Positionen-Text.
// Grow-Rollen sind immer Minijob, Nicht-Grow-Rollen teilen sich den
// gemeinsamen Vertrag. Akzeptiert neues {rollen,vertrag}- und altes
// Array-Format [{rolle,vertrag}].
const GROWER_ROLLEN = ['grower'];

function formatPositionen(ed: unknown): string {
  let rollen: string[] = [];
  let vertrag = '';
  if (Array.isArray(ed)) {
    rollen = ed.map((d: any) => d && d.rolle).filter(Boolean);
    const mitVertrag = ed.find((d: any) => d && d.vertrag && !GROWER_ROLLEN.includes(d.rolle))
      || ed.find((d: any) => d && d.vertrag);
    vertrag = mitVertrag ? mitVertrag.vertrag : '';
  } else if (ed && typeof ed === 'object') {
    const o = ed as any;
    rollen = Array.isArray(o.rollen) ? o.rollen : [];
    vertrag = o.vertrag || '';
  }
  if (rollen.length === 0) return '(Position wird noch festgelegt)';

  const growR = rollen.filter((r) => GROWER_ROLLEN.includes(r));
  const nichtGrowR = rollen.filter((r) => !GROWER_ROLLEN.includes(r));
  const vLabel = vertrag ? (VERTRAG_LABELS[vertrag] || vertrag) : '';

  const join = (arr: string[]) => arr.length === 1
    ? arr[0]
    : arr.slice(0, -1).join(', ') + ' und ' + arr[arr.length - 1];

  const teile: string[] = [];
  if (nichtGrowR.length) {
    teile.push(join(nichtGrowR.map((r) => ROLE_LABELS[r] || r)) + (vLabel ? ` (${vLabel})` : ''));
  }
  if (growR.length) {
    teile.push(join(growR.map((r) => ROLE_LABELS[r] || r)) + ' (Minijob)');
  }
  return teile.join(', ');
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  try {
    const payload = await req.json();
    const record = payload.record || payload.new || payload;
    const oldRecord = payload.old_record || payload.old || {};

    // Nur bei echter Status-Aenderung etwas tun
    const newStatus = record.status;
    const oldStatus = oldRecord.status;
    if (!newStatus || newStatus === oldStatus) {
      return new Response(JSON.stringify({ ok: true, skip: 'kein Status-Wechsel' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Eingangs-Mail kommt von separater Function (send-bewerbung-email)
    if (newStatus === 'eingegangen') {
      return new Response(JSON.stringify({ ok: true, skip: 'eingegangen wird separat gemailt' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!record.email || !record.vorname) {
      return new Response(JSON.stringify({ error: 'Bewerber-Daten unvollstaendig' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Supabase-Client fuer Vereinsdaten
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: verein } = await supabase
      .from('csc_vereine')
      .select('id, name, vorstand_email, ort, plz')
      .eq('id', record.verein_id)
      .single();

    const vereinName = verein?.name || 'Mariana Cannabis';
    const vereinContact = verein?.vorstand_email || Deno.env.get('SMTP_FROM_EMAIL');

    // SMTP-Config
    const smtpHost = Deno.env.get('SMTP_HOST') || 'smtp.ionos.de';
    const smtpPort = parseInt(Deno.env.get('SMTP_PORT') || '465');
    const smtpUser = Deno.env.get('SMTP_USER')!;
    const smtpPassword = Deno.env.get('SMTP_PASSWORD')!;
    const fromEmail = Deno.env.get('SMTP_FROM_EMAIL') || smtpUser;
    const fromName = Deno.env.get('SMTP_FROM_NAME') || 'Mariana Cannabis';
    const replyToEmail = Deno.env.get('REPLY_TO_EMAIL') || fromEmail;

    // Template auswaehlen
    const template = buildTemplate(newStatus, {
      vorname: record.vorname,
      nachname: record.nachname || '',
      vereinName,
      vereinContact: vereinContact || fromEmail || '',
      bewerbungsId: (record.id || '').slice(0, 8).toUpperCase(),
      positionen: formatPositionen(record.eingestellt_details),
      statusLink: record.bewerber_token
        ? STATUS_BASE_URL + '?token=' + encodeURIComponent(String(record.bewerber_token))
        : '',
    });

    if (!template) {
      return new Response(JSON.stringify({ ok: true, skip: 'kein Template fuer Status: ' + newStatus }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Mail senden via nodemailer (korrektes Subject-Encoding fuer Umlaute)
    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: smtpPort,
      secure: smtpPort === 465,
      auth: { user: smtpUser, pass: smtpPassword },
    });

    await transporter.sendMail({
      from: { name: fromName, address: fromEmail },
      to: { name: `${record.vorname} ${record.nachname || ''}`.trim(), address: record.email },
      replyTo: vereinContact || replyToEmail,
      subject: template.subject,
      text: template.text,
      html: template.html,
    });

    console.log(`Status-Mail an ${record.email} (Status: ${newStatus}, Verein: ${vereinName})`);

    return new Response(JSON.stringify({
      ok: true,
      sent_to: record.email,
      status: newStatus,
      verein: vereinName,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });

  } catch (e) {
    console.error('Status-Mail Fehler:', e);
    return new Response(JSON.stringify({
      error: e instanceof Error ? e.message : String(e),
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});

// ============================================================================
// Templates pro Status (unveraendert)
// ============================================================================

interface TemplateData {
  vorname: string;
  nachname: string;
  vereinName: string;
  vereinContact: string;
  bewerbungsId: string;
  positionen: string;
  statusLink: string;
}

interface Template {
  subject: string;
  text: string;
  html: string;
}

function buildTemplate(status: string, data: TemplateData): Template | null {
  const greeting = `Hallo ${data.vorname},`;
  const footer = `\n\nBei Fragen melde dich gerne direkt beim Verein:\n${data.vereinContact}\n\nVG\nDein Mariana-Cannabis-Team`;
  const footerHtml = `<p style="font-size:13px;color:#666;margin-top:24px">Bei Fragen melde dich gerne direkt beim Verein:<br><a href="mailto:${escapeHtml(data.vereinContact)}" style="color:#4caf6a">${escapeHtml(data.vereinContact)}</a></p><p style="font-size:13px;color:#888;margin-top:16px">VG<br>Dein Mariana-Cannabis-Team</p>`;
  const idTag = `\n\nDeine Bewerbungs-ID: ${data.bewerbungsId}`;

  switch (status) {
    case 'in_pruefung': {
      const subject = `Deine Bewerbung bei ${data.vereinName} wird gepr\u00fcft`;
      const text = `${greeting}

danke nochmal f\u00fcr deine Bewerbung bei ${data.vereinName}.

Wir wollten dir kurz Bescheid geben: Der Vorstand hat deine Bewerbung jetzt in Pr\u00fcfung genommen. Innerhalb der n\u00e4chsten Tage bekommst du Bescheid, wie es weitergeht.

Du musst nichts weiter tun.
${idTag}${footer}`;
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:600px;margin:0 auto;padding:24px;color:#222;background:#fafafa">
<div style="background:white;padding:32px;border-radius:12px;border:1px solid #e0e0e0">
<h2 style="color:#4a5a32;margin:0 0 16px 0">Deine Bewerbung wird gepr&uuml;ft</h2>
<p>${escapeHtml(greeting)}</p>
<p>danke nochmal f&uuml;r deine Bewerbung bei <strong>${escapeHtml(data.vereinName)}</strong>.</p>
<p>Wir wollten dir kurz Bescheid geben: <strong>Der Vorstand hat deine Bewerbung jetzt in Pr&uuml;fung genommen.</strong> Innerhalb der n&auml;chsten Tage bekommst du Bescheid, wie es weitergeht.</p>
<p style="background:#f0f2e3;padding:12px;border-radius:6px;border-left:3px solid #4caf6a">Du musst nichts weiter tun.</p>
<p style="font-size:13px;color:#666">Deine Bewerbungs-ID: <code>${escapeHtml(data.bewerbungsId)}</code></p>
${footerHtml}</div></body></html>`;
      return { subject, text, html };
    }

    case 'eingeladen': {
      const subject = `Einladung zum Gespr\u00e4ch bei ${data.vereinName}`;
      const text = `${greeting}

gute Nachricht: ${data.vereinName} m\u00f6chte dich gerne zu einem Gespr\u00e4ch einladen.

Der Vorstand wird sich in den n\u00e4chsten Tagen direkt bei dir melden um einen Termin zu vereinbaren.

Wenn du in der Zwischenzeit Fragen hast oder einen Termin vorschlagen m\u00f6chtest, antworte einfach auf diese Mail oder melde dich direkt unter ${data.vereinContact}.

Wir freuen uns auf das Gespr\u00e4ch!
${idTag}${footer}`;
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:600px;margin:0 auto;padding:24px;color:#222;background:#fafafa">
<div style="background:white;padding:32px;border-radius:12px;border:1px solid #e0e0e0">
<h2 style="color:#4a5a32;margin:0 0 16px 0">Einladung zum Gespr&auml;ch &#127807;</h2>
<p>${escapeHtml(greeting)}</p>
<p style="font-size:16px"><strong>Gute Nachricht:</strong> ${escapeHtml(data.vereinName)} m&ouml;chte dich gerne zu einem Gespr&auml;ch einladen.</p>
<p>Der Vorstand wird sich in den n&auml;chsten Tagen direkt bei dir melden, um einen Termin zu vereinbaren.</p>
<p style="background:#e8f5e9;padding:14px;border-radius:6px;border-left:3px solid #4caf6a"><strong>Wenn du in der Zwischenzeit Fragen hast</strong> oder einen Termin vorschlagen m&ouml;chtest, antworte einfach auf diese Mail oder melde dich direkt unter <a href="mailto:${escapeHtml(data.vereinContact)}" style="color:#4caf6a">${escapeHtml(data.vereinContact)}</a>.</p>
<p>Wir freuen uns auf das Gespr&auml;ch!</p>
<p style="font-size:13px;color:#666">Deine Bewerbungs-ID: <code>${escapeHtml(data.bewerbungsId)}</code></p>
${footerHtml}</div></body></html>`;
      return { subject, text, html };
    }

    case 'warteliste': {
      const subject = `Update zu deiner Bewerbung bei ${data.vereinName}`;
      const text = `${greeting}

danke f\u00fcr deine Bewerbung bei ${data.vereinName}.

Wir haben dich f\u00fcr folgende Position(en) vorgemerkt: ${data.positionen}.

Aktuell ist dort leider keine Stelle frei. Wir setzen dich auf unsere Warteliste und melden uns direkt bei dir, sobald etwas Passendes frei wird.

Deine Bewerbung bleibt aktiv im System und wird im n\u00e4chsten Auswahl-Durchgang erneut ber\u00fccksichtigt.
${idTag}${footer}`;
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:600px;margin:0 auto;padding:24px;color:#222;background:#fafafa">
<div style="background:white;padding:32px;border-radius:12px;border:1px solid #e0e0e0">
<h2 style="color:#4a5a32;margin:0 0 16px 0">Update zu deiner Bewerbung</h2>
<p>${escapeHtml(greeting)}</p>
<p>danke f&uuml;r deine Bewerbung bei <strong>${escapeHtml(data.vereinName)}</strong>.</p>
<p>Wir haben dich f&uuml;r folgende Position(en) vorgemerkt: <strong>${escapeHtml(data.positionen)}</strong>.</p>
<p>Aktuell ist dort leider keine Stelle frei. Wir setzen dich auf unsere <strong>Warteliste</strong>.</p>
<p style="background:#fff4e0;padding:12px;border-radius:6px;border-left:3px solid #ffb74d">Sobald sich etwas &auml;ndert, melden wir uns direkt bei dir. Deine Bewerbung bleibt aktiv im System.</p>
<p style="font-size:13px;color:#666">Deine Bewerbungs-ID: <code>${escapeHtml(data.bewerbungsId)}</code></p>
${footerHtml}</div></body></html>`;
      return { subject, text, html };
    }

    case 'angenommen': {
      const subject = `Willkommen bei ${data.vereinName}!`;

      // Vertragsdaten-Block nur, wenn ein Status-Token vorliegt
      const vertragsText = data.statusLink
        ? `\n\nDamit wir deinen Arbeitsvertrag vorbereiten können, brauchen wir noch ein paar Angaben von dir. Bitte öffne deine persönliche Status-Seite und fülle dort das Formular "Daten für den Arbeitsvertrag" aus:\n\n${data.statusLink}`
        : '';

      const text = `${greeting}

herzlich willkommen bei ${data.vereinName}!

Wir freuen uns sehr, dich für folgende Position(en) an Bord zu holen: ${data.positionen}.

Der Vorstand wird sich in den nächsten Tagen mit allen Details bei dir melden:

- Vertrag und Onboarding
- Erster Arbeitstag
- Schlüsselausgabe / Zugang
- Sicherheits- und Präventionsschulungen${vertragsText}

Falls du vorab Fragen hast: ${data.vereinContact}
${idTag}${footer}`;

      const vertragsHtml = data.statusLink
        ? `<div style="background:#e8f5e9;padding:16px;border-radius:6px;border-left:3px solid #4caf6a;margin:16px 0">
<p style="margin:0 0 12px 0">Damit wir deinen <strong>Arbeitsvertrag</strong> vorbereiten k&ouml;nnen, brauchen wir noch ein paar Angaben von dir. Bitte f&uuml;lle das Formular &bdquo;Daten f&uuml;r den Arbeitsvertrag&ldquo; auf deiner pers&ouml;nlichen Status-Seite aus:</p>
<p style="margin:0"><a href="${escapeHtml(data.statusLink)}" style="display:inline-block;background:#4caf6a;color:#ffffff;padding:11px 22px;border-radius:6px;text-decoration:none;font-weight:600">Status-Seite &ouml;ffnen</a></p>
</div>`
        : '';

      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:600px;margin:0 auto;padding:24px;color:#222;background:#fafafa">
<div style="background:white;padding:32px;border-radius:12px;border:2px solid #4caf6a">
<h2 style="color:#4caf6a;margin:0 0 16px 0;font-size:24px">&#127881; Herzlich willkommen!</h2>
<p>${escapeHtml(greeting)}</p>
<p style="font-size:16px">wir freuen uns sehr, dich bei <strong>${escapeHtml(data.vereinName)}</strong> an Bord zu holen!</p>
<p style="background:#e8f5e9;padding:12px;border-radius:6px;border-left:3px solid #4caf6a">Deine Position(en): <strong>${escapeHtml(data.positionen)}</strong></p>
<p>Der Vorstand wird sich in den n&auml;chsten Tagen mit allen Details bei dir melden:</p>
<ul style="line-height:1.8">
<li>Vertrag und Onboarding</li>
<li>Erster Arbeitstag</li>
<li>Schl&uuml;sselausgabe und Zugang</li>
<li>Sicherheits- und Pr&auml;ventionsschulungen</li>
</ul>
${vertragsHtml}
<p style="background:#e8f5e9;padding:12px;border-radius:6px">Falls du vorab Fragen hast: <a href="mailto:${escapeHtml(data.vereinContact)}" style="color:#4caf6a">${escapeHtml(data.vereinContact)}</a></p>
<p style="font-size:13px;color:#666">Deine Bewerbungs-ID: <code>${escapeHtml(data.bewerbungsId)}</code></p>
${footerHtml}</div></body></html>`;
      return { subject, text, html };
    }

    case 'abgelehnt': {
      const subject = `R\u00fcckmeldung zu deiner Bewerbung bei ${data.vereinName}`;
      const text = `${greeting}

danke, dass du dich bei ${data.vereinName} beworben hast.

Wir haben uns eure Unterlagen genau angeschaut und uns nach reiflicher \u00dcberlegung entschieden, dich aktuell nicht in unser Team aufzunehmen.

Das hat nichts mit deiner Qualifikation zu tun, sondern liegt an der aktuellen Bedarfslage und Bewerber-Anzahl. Wir wissen, dass eine Absage immer schade ist, und wir bedauern es.

Falls dich andere Mariana-Vereine in deiner Region interessieren oder du dich sp\u00e4ter erneut bewerben m\u00f6chtest: deine Bewerbung wird sicher gel\u00f6scht, du kannst dich also jederzeit neu bewerben.

Alles Gute f\u00fcr deinen weiteren Weg!
${idTag}${footer}`;
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:600px;margin:0 auto;padding:24px;color:#222;background:#fafafa">
<div style="background:white;padding:32px;border-radius:12px;border:1px solid #e0e0e0">
<h2 style="color:#4a5a32;margin:0 0 16px 0">R&uuml;ckmeldung zu deiner Bewerbung</h2>
<p>${escapeHtml(greeting)}</p>
<p>danke, dass du dich bei <strong>${escapeHtml(data.vereinName)}</strong> beworben hast.</p>
<p>Wir haben uns eure Unterlagen genau angeschaut und uns nach reiflicher &Uuml;berlegung entschieden, <strong>dich aktuell nicht in unser Team aufzunehmen</strong>.</p>
<p>Das hat nichts mit deiner Qualifikation zu tun, sondern liegt an der aktuellen Bedarfslage. Wir wissen, dass eine Absage immer schade ist, und wir bedauern es.</p>
<p style="background:#f0f2e3;padding:12px;border-radius:6px;border-left:3px solid #4caf6a">Falls dich andere Mariana-Vereine in deiner Region interessieren oder du dich sp&auml;ter erneut bewerben m&ouml;chtest: deine Bewerbung wird sicher gel&ouml;scht, du kannst dich also jederzeit neu bewerben.</p>
<p>Alles Gute f&uuml;r deinen weiteren Weg!</p>
<p style="font-size:13px;color:#666">Deine Bewerbungs-ID: <code>${escapeHtml(data.bewerbungsId)}</code></p>
${footerHtml}</div></body></html>`;
      return { subject, text, html };
    }

    default:
      return null;
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
