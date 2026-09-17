package handlers

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"
)

// Push do S.O.S. (docs/sos-rede-motoristas.md, seção 10). O app grava
// `presence/{uid}` = {token FCM, lat/lng com 2 casas, at}; aqui o raio é
// calculado no servidor e cada motorista perto recebe uma mensagem de
// NOTIFICAÇÃO (o Play Services exibe sem o processo do app vivo — MIUI mata
// mensagem de dados). Sem geohash: dezenas de motoristas, uma leitura de
// coleção por S.O.S. ponytail: teto = milhares de presenças por pedido; o
// upgrade é campo `cell` + range por prefixo.

const (
	sosRaioM       = 50_000.0 // decisão de 14/09: 50 km
	presencaIdade  = 24 * time.Hour
	sosPushTimeout = 8 * time.Second // o app espera 12 s pela resposta do POST
	sosPushLoteMax = 500             // limite do SendEach (firebase-admin-go)
)

var sosTipoLabel = map[string]string{
	"ferramenta": "Ferramenta", "pneu": "Pneu", "combustivel": "Combustível",
	"mecanica": "Mecânica", "reboque": "Reboque", "saude": "Saúde", "outro": "Ajuda",
}

type presenca struct {
	UID, Token string
	Lat, Lng   float64
}

type destinatario struct {
	UID, Token string
	DistM      float64
}

func haversineM(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371000.0
	toRad := math.Pi / 180
	dLat := (lat2 - lat1) * toRad
	dLng := (lng2 - lng1) * toRad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*toRad)*math.Cos(lat2*toRad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * r * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// sosDestinatarios é pura pra ser testável: quem está no raio, menos o dono,
// um por token (reinstalação deixa presença velha com o mesmo token).
func sosDestinatarios(ps []presenca, lat, lng, raioM float64, dono string) []destinatario {
	vistos := map[string]bool{}
	var out []destinatario
	for _, p := range ps {
		if p.UID == dono || p.Token == "" || vistos[p.Token] {
			continue
		}
		d := haversineM(lat, lng, p.Lat, p.Lng)
		if d > raioM {
			continue
		}
		vistos[p.Token] = true
		out = append(out, destinatario{UID: p.UID, Token: p.Token, DistM: d})
	}
	return out
}

func kmTexto(m float64) string {
	if m < 1000 {
		return "menos de 1 km"
	}
	return fmt.Sprintf("%d km", int(math.Round(m/1000)))
}

func (h *Sos) lerPresencas(ctx context.Context) ([]presenca, error) {
	it := h.fs.Collection("presence").
		Where("at", ">", time.Now().Add(-presencaIdade)).Documents(ctx)
	defer it.Stop()
	var out []presenca
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return out, err
		}
		d := doc.Data()
		tok, _ := d["token"].(string)
		lat, _ := d["lat"].(float64)
		lng, _ := d["lng"].(float64)
		out = append(out, presenca{UID: doc.Ref.ID, Token: tok, Lat: lat, Lng: lng})
	}
	return out, nil
}

// notificarAbertura avisa quem está no raio. Erro nunca sobe: o S.O.S. já
// existe e quem está com o app aberto vê pelo stream.
func (h *Sos) notificarAbertura(ctx context.Context, id, dono string, in sosCreateIn, p perfil) {
	if h.msg == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, sosPushTimeout)
	defer cancel()
	ps, err := h.lerPresencas(ctx)
	if err != nil {
		log.Printf("sos push %s: presencas: %v", id, err)
		return
	}
	dest := sosDestinatarios(ps, in.Lat, in.Lng, sosRaioM, dono)
	caminhao := in.Caminhao
	if in.Cor != "" {
		caminhao += " " + in.Cor
	}
	var msgs []*messaging.Message
	for _, d := range dest {
		msgs = append(msgs, &messaging.Message{
			Token: d.Token,
			Notification: &messaging.Notification{
				Title: "Motorista pedindo ajuda a " + kmTexto(d.DistM),
				Body:  sosTipoLabel[in.Tipo] + " · " + p.Nome + " · " + caminhao,
			},
			Data:    map[string]string{"sosId": id},
			Android: androidAlta(),
		})
	}
	ok, falha := h.enviar(ctx, msgs, dest)
	log.Printf("sos push %s: presencas=%d perto=%d ok=%d falha=%d", id, len(ps), len(dest), ok, falha)
}

// notificarAceite avisa o dono que alguém vem.
func (h *Sos) notificarAceite(ctx context.Context, id, donoUID, ajudanteNome string) {
	if h.msg == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, sosPushTimeout)
	defer cancel()
	doc, err := h.fs.Collection("presence").Doc(donoUID).Get(ctx)
	if err != nil {
		log.Printf("sos push aceite %s: presenca do dono: %v", id, err)
		return
	}
	tok, _ := doc.Data()["token"].(string)
	if tok == "" {
		return
	}
	msg := &messaging.Message{
		Token: tok,
		Notification: &messaging.Notification{
			Title: ajudanteNome + " vai te ajudar",
			Body:  "Abra o pedido pra ver o telefone e combinar.",
		},
		Data:    map[string]string{"sosId": id},
		Android: androidAlta(),
	}
	ok, falha := h.enviar(ctx, []*messaging.Message{msg}, []destinatario{{UID: donoUID, Token: tok}})
	log.Printf("sos push aceite %s: ok=%d falha=%d", id, ok, falha)
}

func androidAlta() *messaging.AndroidConfig {
	return &messaging.AndroidConfig{
		Priority: "high",
		Notification: &messaging.AndroidNotification{
			Priority: messaging.PriorityHigh,
			Sound:    "default",
		},
	}
}

// enviar em lotes de 500; token morto (reinstalou, desinstalou) apaga a
// presença pra não insistir.
func (h *Sos) enviar(ctx context.Context, msgs []*messaging.Message, dest []destinatario) (ok, falha int) {
	for i := 0; i < len(msgs); i += sosPushLoteMax {
		j := min(i+sosPushLoteMax, len(msgs))
		resp, err := h.msg.SendEach(ctx, msgs[i:j])
		if err != nil {
			log.Printf("sos push: SendEach: %v", err)
			falha += j - i
			continue
		}
		ok += resp.SuccessCount
		falha += resp.FailureCount
		for k, r := range resp.Responses {
			if r.Error != nil && messaging.IsUnregistered(r.Error) {
				_, _ = h.fs.Collection("presence").Doc(dest[i+k].UID).Delete(ctx)
			}
		}
	}
	return ok, falha
}
